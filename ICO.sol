// SPDX-License-Identifier: No License (None)
pragma solidity 0.8.19;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IVesting {
    function allocateTokens(
        address to, // beneficiary of tokens
        uint256 amount, // amount of token
        uint256 unlockPercentage,   // percentage (with 2 decimals) of initially unlocked token
        uint256 cliffFinish,       // Timestamp (unix time) when starts vesting. First vesting will be at this time
        uint256 vestingPercentage,  // percentage (with 2 decimals) of tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 vestingInterval     // interval (in seconds) of vesting (i.e. 30 days)
    ) external;
}

contract ICO is Ownable {
    address public ICOtoken;    // ICO token and receiving token must have 18 decimals
    address public vestingContract; 
    //address public paymentToken = 0x7873d09AF3d6965988831C60c7D38DBbd2eAEAB0; // test4
    address public paymentToken = 0xbf6c50889d3a620eb42C0F188b65aDe90De958c4; //BUSDT

    uint256 public unlockPercentage = 500; // percentage (with 2 decimals) of initially unlocked token
    uint256 public cliffPeriod = 180 days;    // vesting period (in seconds)
    uint256 public vestingPercentage = 500;        // percentage (with 2 decimals) of locked tokens will be unlocked every interval (i.e. 10% per 30 days)
    uint256 public vestingInterval = 30 days;     // interval (in seconds) of vesting (i.e. 30 days)
    uint256 public startDate = 1707483000;

    struct Round {
        uint256 amount;     // amount of tokens to sell in this round
        uint128 price;      // price per token (in payTokens value)
        uint128 roundStarts; // timestamp when round starts
        uint256 totalSold;  // amount of tokens sold 
        uint256 totalReceived;  // total payments received in round
    }

    Round[] public rounds;
    uint256 public currentRound;
    bool public isPause;

    event BuyToken(uint256 round, uint256 amountToPay, uint256 amountToBuy);
    event RoundEnds(uint256 round, uint256 starTime, uint256 endTime, uint256 lastSoldAmount);

    constructor (address _ICOtoken, address _vestingContract) {
        ICOtoken = _ICOtoken;
        vestingContract = _vestingContract;
        IERC20(_ICOtoken).approve(_vestingContract, type(uint256).max);
    }

    modifier checkRound() {
        require(currentRound < rounds.length, "ICO finished");
        require(block.timestamp >= startDate, "ICO is not started yet");
        require(!isPause, "ICO is paused");
        _;
    }

    // Buy ICO tokens
    function buyToken(
        uint256 amountToBuy,    // amount of token to buy
        address buyer           // buyer address
    ) public checkRound {
        require(buyer != address(0), "Incorrect buyer");
        uint256 _currentRound = currentRound;   // use local variable to save gas
        Round storage r = rounds[_currentRound];
        if(r.roundStarts == 0) {
            if(_currentRound == 0) r.roundStarts = uint128(startDate);
            else r.roundStarts = uint128(block.timestamp);
        }

        if(r.totalSold + amountToBuy >= r.amount) {
            amountToBuy = r.amount - r.totalSold;
            currentRound++;
            emit RoundEnds(_currentRound, r.roundStarts, block.timestamp, amountToBuy);
        }

        uint256 amountToPay = amountToBuy * r.price / 1e18;
        r.totalSold += amountToBuy;
        r.totalReceived += amountToPay;
        safeTransferFrom(paymentToken, msg.sender, owner(), amountToPay);
        // set vesting
        uint256 finishVesting = block.timestamp + cliffPeriod;
        uint256 unlockedAmount = amountToBuy * unlockPercentage / 10000;
        uint256 lockedAmount = amountToBuy - unlockedAmount;
        if (lockedAmount != 0) {
            //safeTransfer(ICOtoken, vestingContract, lockedAmount);
            IVesting(vestingContract).allocateTokens(buyer, lockedAmount, 0, finishVesting, vestingPercentage, vestingInterval);
        }
        safeTransfer(ICOtoken, buyer, unlockedAmount);
        emit BuyToken(_currentRound, amountToPay, amountToBuy);
    }

    function addRound(
        uint256 amount,     // amount of tokens to sell in this round
        uint128 price       // price per token (in USD with 18 decimals)     
    ) external onlyOwner {
        rounds.push(Round(amount, price, 0, 0, 0));
    }

    function changRound(
        uint256 roundId,    // round to change
        uint256 amount,     // amount of tokens to sell in this round
        uint128 price       // price per token (in USD with 18 decimals) 
    ) external onlyOwner {
        require(roundId < rounds.length, "wrong round id");
        rounds[roundId].amount = amount;
        rounds[roundId].price = price;
    }

    function getRoundsNumber() external view returns(uint256 roundsNumber) {
        return rounds.length;
    }

    function getCurrentRound() external view returns(Round memory r) {
        if(currentRound < rounds.length) r = rounds[currentRound];
    }
    
    function setPause(bool pause) external onlyOwner {
        isPause = pause;
    }

    function setStartDate(uint256 _startDate) external onlyOwner {
        startDate = _startDate;
    }

    function setVesting(
        address _vestingContract,  // address of vesting contract or address(0) to don't change
        uint256 _unlockPercentage, // percentage of initially unlocked token
        uint256 _cliffPeriod,    // vesting period (in seconds)
        uint256 _vestingPercentage,  // percentage of locked tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 _vestingInterval     // interval (in seconds) of vesting (i.e. 30 days)
    ) external onlyOwner {
        if(vestingContract != _vestingContract && _vestingContract != address(0)) {
            IERC20(ICOtoken).approve(vestingContract, 0);
            IERC20(ICOtoken).approve(_vestingContract, type(uint256).max);
            vestingContract = _vestingContract;
        }
        unlockPercentage = _unlockPercentage;
        cliffPeriod = _cliffPeriod;
        vestingPercentage = _vestingPercentage;
        vestingInterval = _vestingInterval;
    }

    // allow to receive ERC223 tokens
    function tokenReceived(address, uint256, bytes memory) external virtual returns(bytes4) {
        return this.tokenReceived.selector;
    }

    event Rescue(address _token, uint256 _amount);
    function rescueTokens(address _token) onlyOwner external {
        uint256 amount;
        if (_token == address(0)) {
            amount = address(this).balance;
            safeTransferCLO(msg.sender, amount);
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            safeTransfer(_token, msg.sender, amount);
        }
        emit Rescue(_token, amount);
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferCLO(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: CLO_TRANSFER_FAILED');
    }
}

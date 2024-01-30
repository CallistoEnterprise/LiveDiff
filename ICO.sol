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
}

interface IVesting {
    function allocateTokens(
        address to, // beneficiary of tokens
        uint256 amount, // amount of token
        uint256 unlockPercentage,   // percentage of initially unlocked token
        uint256 finishVesting,       // Timestamp (unix time) when starts vesting. First vesting will be at this time
        uint256 cliffPercentage,  // percentage of tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 cliffInterval     // interval (in seconds) of vesting (i.e. 30 days)
    ) external;
}

contract ICO is Ownable {
    address public ICOtoken;    // ICO token and receiving token must have 18 decimals
    address public vestingContract; 

    uint256 public unlockPercentage = 50; // percentage of initially unlocked token
    uint256 public vestingPeriod = 182 days;    // vesting period (in seconds)
    uint256 public cliffPercentage = 33;        // percentage of locked tokens will be unlocked every interval (i.e. 10% per 30 days)
    uint256 public cliffInterval = 30 days;     // interval (in seconds) of vesting (i.e. 30 days)

    struct Round {
        uint256 amount;     // amount of tokens to sell in this round
        uint64 startDate;   // timestamp when round starts
        uint64 endDate;     // timestamp when round finishes
        uint128 price;      // price per token (in payTokens value)
        address payTokens;  // token should be paid (address(0) - native coin)
        uint256 totalSold;  // amount of tokens sold 
        uint256 totalReceived;  // total payments received in round
    }

    Round[] public rounds;  // starts from round 1
    uint256 public currentRound;
    bool public isPause;

    event BuyToken(uint256 round, address paidToken, uint256 paidAmount, uint256 sellAmount);

    constructor (address _ICOtoken, address _vestingContract) {
        rounds.push();  // starts from round 1
        ICOtoken = _ICOtoken;
        vestingContract = _vestingContract;
    }

    modifier checkRound() {
        uint256 len = rounds.length;
        uint256 i = currentRound;
        for (; i<len; i++) {
            if(rounds[i].endDate >= block.timestamp) break; 
        }
        currentRound = i;
        require(i < len, "ICO finished");
        require(block.timestamp >= rounds[i].startDate, "ICO round is not started yet");
        require(!isPause, "ICO is paused");
        _;
    }

    // returns current or next (if it was not started yet) round information
    function getRound() external view returns(Round memory round) {
        uint256 len = rounds.length;
        uint256 i = currentRound;
        for (; i<len; i++) {
            if(rounds[i].endDate >= block.timestamp) break; 
        }   
        if (i < len) return rounds[i];
    }

    receive() external payable {
        buyToken(msg.value);
    }

    // Buy ICO tokens for amount of pay tokens
    function buyToken(uint256 amount) public payable checkRound {
        Round storage r = rounds[currentRound];
        uint256 rest;
        uint256 sellAmount = amount * 1e18 / r.price;
        if(r.totalSold + sellAmount > r.amount) {
            sellAmount = r.amount - r.totalSold;
            rest = amount - (sellAmount * r.price / 1e18);  // amount to refund user
        }
        if (r.payTokens == address(0)) {
            require(amount == msg.value, "wrong amount");
            if(rest != 0) safeTransferCLO(msg.sender, rest);
        }
        else {
            require(msg.value == 0, "Should pay with tokens");
            safeTransferFrom(r.payTokens, msg.sender, address(this), amount-rest);
        }
        uint256 finishVesting = block.timestamp + vestingPeriod;
        uint256 unlockedAmount = sellAmount * unlockPercentage / 100;
        uint256 lockedAmount = sellAmount - unlockedAmount;
        if (lockedAmount != 0) {
            safeTransfer(ICOtoken, vestingContract, lockedAmount);
            IVesting(vestingContract).allocateTokens(msg.sender, lockedAmount, 0, finishVesting, cliffPercentage, cliffInterval);
        }
        safeTransfer(ICOtoken, msg.sender, unlockedAmount);
        emit BuyToken(currentRound, r.payTokens, amount-rest, sellAmount);
    }

    function addRound(
        uint256 amount,     // amount of tokens to sell in this round
        uint64 startDate,   // timestamp when round starts
        uint64 endDate,     // timestamp when round finishes
        uint128 price,       // price per token       
        address payTokens  // token should be paid (address(0) - native coin)
    ) external onlyOwner {
        Round storage r = rounds[rounds.length-1];
        require(r.endDate < startDate, "New round must start after previous");
        require(startDate < endDate && startDate > block.timestamp, "wrong dates");
        rounds.push(Round(amount, startDate, endDate, price, payTokens, 0, 0));
    }

    function changRound(
        uint256 roundId,    // round to change
        uint256 amount,     // amount of tokens to sell in this round
        uint64 startDate,   // timestamp when round starts
        uint64 endDate,     // timestamp when round finishes
        uint128 price,       // price per token
        address payTokens  // token should be paid (address(0) - native coin)
    ) external onlyOwner {
        require(roundId > 0 && roundId < rounds.length, "wrong round id");
        //require(rounds[roundId].startDate > block.timestamp, "Round already started");
        require(rounds[roundId-1].endDate < startDate, "Round must start after previous");
        if(roundId < rounds.length-1) require(rounds[roundId+1].startDate > endDate, "Round must finish before next");
        require(startDate < endDate, "wrong dates");        
        rounds[roundId].amount = amount;
        rounds[roundId].startDate = startDate;
        rounds[roundId].endDate = endDate;
        rounds[roundId].price = price;
        rounds[roundId].payTokens = payTokens;
    }

    function setPause(bool pause) external onlyOwner {
        isPause = pause;
    }

    function setVesting(
        address _vestingContract,  // address of vesting contract
        uint256 _unlockPercentage, // percentage of initially unlocked token
        uint256 _vestingPeriod,    // vesting period (in seconds)
        uint256 _cliffPercentage,  // percentage of locked tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 _cliffInterval     // interval (in seconds) of vesting (i.e. 30 days)
    ) external onlyOwner {
        vestingContract = _vestingContract;
        unlockPercentage = _unlockPercentage;
        vestingPeriod = _vestingPeriod;
        cliffPercentage = _cliffPercentage;
        cliffInterval = _cliffInterval;
    }

    // allow to receive ERC223 tokens
    function tokenReceived(address _from, uint256, bytes memory) external virtual returns(bytes4) {
        require(msg.sender == ICOtoken && _from == owner(), "ERC223 wrong token");
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

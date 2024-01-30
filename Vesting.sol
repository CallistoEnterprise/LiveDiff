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
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
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
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

abstract contract ERC223Recipient { 
    mapping(address => bool) public depositors; // address of users who has right to deposit and allocate tokens

    modifier onlyDepositor() {
        require(depositors[msg.sender], "Only depositors allowed");
        _;
    }

    /**
    * @dev Standard ERC223 function that will handle incoming token transfers.
    */
    function tokenReceived(address _from, uint256, bytes memory) external virtual returns(bytes4) {
        require(depositors[_from], "Only depositors allowed");
        return this.tokenReceived.selector;
    }

}

contract Vesting is Ownable, ERC223Recipient {
    address public vestedToken;
    uint256 public vestingPeriod;   // vesting period of time (in seconds)
    uint256 public unlockPercentage;   // percentage of initially unlocked token
    uint256 public cliffPercentage;  // percentage of tokens will be unlocked every interval (i.e. 10% per 30 days)
    uint256 public cliffInterval;    // interval (in seconds) of vesting (i.e. 30 days)        

    uint256 public totalAllocated;
    uint256 public totalClaimed;
    
    struct Allocation {
        uint256 amount; // allocated amount
        uint256 finishVesting; // Timestamp (unix time) when finish vesting. First release will be at this time
    }

    mapping(address beneficiary => Allocation[]) public beneficiaries; // beneficiary => Allocation
    mapping(address => uint256) public claimedAmount;   // beneficiary => already claimed amount

    event SetDepositor(address depositor, bool enable);
    event Claim(address indexed beneficiary, uint256 amount);
    event AddAllocation(
        address indexed to,         // beneficiary of tokens
        uint256 amount,             // amount of token
        uint256 unlockPercentage,   // percentage of initially unlocked token
        uint256 finishVesting,       // Timestamp (unix time) when finish vesting. First release will be at this time
        uint256 cliffPercentage,  // percentage of tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 cliffInterval     // interval (in seconds) of vesting (i.e. 30 days)        
    );
    event Rescue(address _token, uint256 _amount);

    constructor (
        address _vestedToken,        // vesting token
        uint256 _vestingPeriod,      // vesting period of time (in seconds)
        uint256 _unlockPercentage,   // percentage of initially unlocked token
        uint256 _cliffPercentage,    // percentage of tokens will be unlocked every interval (i.e. 10% per 30 days)
        uint256 _cliffInterval       // interval (in seconds) of vesting (i.e. 30 days) 
    ) {
        require(_vestedToken != address(0));
        vestedToken = _vestedToken;
        vestingPeriod = _vestingPeriod;
        unlockPercentage = _unlockPercentage;
        cliffPercentage = _cliffPercentage;
        cliffInterval = _cliffInterval;
    }

    // Depositor has right to transfer token to contract and allocate token to the beneficiary
    function setDepositor(address depositor, bool enable) external onlyOwner {
        depositors[depositor] = enable;
        emit SetDepositor(depositor, enable);
    }

    function allocateTokens(
        address to, // beneficiary of tokens
        uint256 amount // amount of token
    )
        external
        onlyDepositor
    {
        require(beneficiaries[to].length < 100, "Too many allocation, use another address");
        uint256 finishVesting = block.timestamp + vestingPeriod;
        require(amount <= getUnallocatedAmount(), "Not enough tokens");
        beneficiaries[to].push(Allocation(amount, finishVesting));
        totalAllocated += amount;
        // Check ERC223 compatibility of the beneficiary 
        if (isContract(to)) {
            ERC223Recipient(to).tokenReceived(address(this), 0, "");
        }
        claimBehalf(to);    // claim to user initially unlocked amount
        emit AddAllocation(to, amount, unlockPercentage, finishVesting, cliffPercentage, cliffInterval);
    }

    function claim() external {
        claimBehalf(msg.sender);
    }

    function claimBehalf(address beneficiary) public {
        uint256 unlockedAmount = getUnlockedAmount(beneficiary);
        if(unlockedAmount == 0) return;
        claimedAmount[beneficiary] += unlockedAmount;
        totalClaimed += unlockedAmount;
        safeTransfer(vestedToken, beneficiary, unlockedAmount);
        emit Claim(beneficiary, unlockedAmount);
    }

    function getUnlockedAmount(address beneficiary) public view returns(uint256 unlockedAmount) {
        uint256 len = beneficiaries[beneficiary].length;
        for (uint256 i = 0; i < len; i++) {
            Allocation storage b = beneficiaries[beneficiary][i];
            uint256 amount = b.amount;
            uint256 unlocked = amount * unlockPercentage / 100;
            if (b.finishVesting <= block.timestamp) {
                uint256 intervals = (block.timestamp - b.finishVesting) / cliffInterval + 1;
                unlocked = unlocked + (amount * intervals * cliffPercentage / 100);
            }
            if (unlocked > amount) unlocked = amount;
            unlockedAmount += unlocked;
        }
        unlockedAmount = unlockedAmount - claimedAmount[beneficiary];
    }

    function getUnallocatedAmount() public view returns(uint256 amount) {
        amount = IERC20(vestedToken).balanceOf(address(this));
        uint256 unclaimed = totalAllocated - totalClaimed;
        amount = amount - unclaimed;
    }

    function rescueTokens(address _token) onlyOwner external {
        uint256 amount;
        if (_token == vestedToken) {
            amount = getUnallocatedAmount();
        } else {
            amount = IERC20(_token).balanceOf(address(this));
        }

        safeTransfer(_token, msg.sender, amount);
        emit Rescue(_token, amount);
    }

    /**
     * @dev Returns true if `account` is a contract.
     *
     * This test is non-exhaustive, and there may be false-negatives: during the
     * execution of a contract's constructor, its address will be reported as
     * not containing a contract.
     *
     * > It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
    
    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }
}
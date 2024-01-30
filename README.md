# LiveDiff

## Vesting contract functions to use in UI

### View function `getUnlockedAmount`

```Solidity
    function getUnlockedAmount(address beneficiary) public view returns(uint256 unlockedAmount);
```

Returns amount of tokens that user (beneficiary) can claim. Show this amount in UI.

### `Claim`

```Solidity
    function claim() external;
```

This function claims unlocked tokens for user.


## ICO contract functions to use in UI

### View function `getRound`

```Solidity
    function getRound() external view returns(Round memory round); 

    struct Round {
        uint256 amount;     // amount of tokens to sell in this round
        uint64 startDate;   // timestamp when round starts
        uint64 endDate;     // timestamp when round finishes
        uint128 price;      // price per token (in payTokens value)
        address payTokens;  // token should be paid (address(0) - native coin)
        uint256 totalSold;  // amount of tokens sold 
        uint256 totalReceived;  // total payments received in round
    }
```

Returns `Round` structure for current ICO round. If current round is finished, but the next round is not started yet the function returns `Round` structure for the next round.
If no round is available the `Round` structure will be empty.

### View function `rounds`

```Solidity
    function rounds(uint256 roundId) external view returns(Round memory round);
```

Returns `Round` structure for specific ICO round. Rounds starts from 1.

### `buyToken`

```Solidity
    function buyToken(uint256 amount) external payable;
```

Allow users to buy tokens from ICO. The `amount` parameter is an amount that user wants to pay (in `payTokens`).
- If user will pay in tokens, you should `approve` tokens for ICO contract before call function `buyToken`.
- If pay with native coin (like CLO), user should transfer the required amount of coin to the ICO contract.

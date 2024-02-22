# LiveDiff

## Deployed contracts

### LiveDIFF token

- [0xdf4Da43DD3E9918F0784f8c92b8aa1b304C43243](https://explorer.callisto.network/token/0xdf4Da43DD3E9918F0784f8c92b8aa1b304C43243/read-contract)

### Multisig wallets

1. Platform rewards [0xaAB2f1727703c227a47539820213839787F1aA45](https://explorer.callisto.network/address/0xaAB2f1727703c227a47539820213839787F1aA45/read-contract)
2. Airdrop [0xb6C5977fD3380936b133ee5FaFbB3D38A6Dd358f](https://explorer.callisto.network/address/0xb6C5977fD3380936b133ee5FaFbB3D38A6Dd358f/read-contract)
3. Liquidity Providers (3rd party) [0x09cc8fFbe632b4261DB345e99C8472CC4FE69126](https://explorer.callisto.network/address/0x09cc8fFbe632b4261DB345e99C8472CC4FE69126/read-contract)
4. Marketing [0xfb206601581eF6Ef900C4D88695A2A5D98D57363](https://explorer.callisto.network/address/0xfb206601581eF6Ef900C4D88695A2A5D98D57363/read-contract)
5. Team (owner of ICO, Vesting, Token contracts) [0x5e0B6b0cC0c037FbE6E774624e1adf01c9CDE3D3](https://explorer.callisto.network/address/0x5e0B6b0cC0c037FbE6E774624e1adf01c9CDE3D3/read-contract)
6. Development fund [0x589Bc41Eb9E8bF7bf26103B0390bd1F25a2a6c78](https://explorer.callisto.network/address/0x589Bc41Eb9E8bF7bf26103B0390bd1F25a2a6c78/read-contract)
7. Dex liquidity [0xD320CA2C33ffD00ce1A1e41055adefD658292561](https://explorer.callisto.network/address/0xD320CA2C33ffD00ce1A1e41055adefD658292561/read-contract)

### Vesting contract
- [0xe5A5837b96176d6E47E541F186B2348DED2c0A1d](https://explorer.callisto.network/address/0xe5A5837b96176d6E47E541F186B2348DED2c0A1d/read-contract)

### ICO contract

- [0x08b60BC7991EeC46Dae2db4C4f08aD9516659339](https://explorer.callisto.network/address/0x08b60BC7991EeC46Dae2db4C4f08aD9516659339/read-contract)

## Vesting contract functions to use in UI

### View function `getUnlockedAmount`

```Solidity
    function getUnlockedAmount(address beneficiary) public view returns(uint256 unlockedAmount, uint256 lockedAmount, uint256 nextUnlock);
```

Returns amount of tokens that user (beneficiary) can claim. Show this amount in UI.

### `claim` and `claimBehalf`

```Solidity
    // claim unlocked tokens by msg.sender
    function claim() external;

    // claim unlocked tokens behalf beneficiary
    function claimBehalf(address beneficiary) public;
```

This function claims unlocked tokens for user.


## ICO contract functions to use in UI

### View functions `getRound` and `getCurrentRound()`

```Solidity
    // return info about arbitrary round
    function getRound(uint256 roundId) external view returns(Round memory round); 
    // return info about current round
    function getCurrentRound() external view returns(Round memory r);

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

Allow users to buy tokens from ICO. The `amount` parameter is an amount that user wants to buy.
- user should `approve` tokens for ICO contract before call function `buyToken`.

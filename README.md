# Polkaswitch Token Contracts
This repository contains token contracts, vesting contracts and staking contacts for Polkaswitch.

## Token Requrirement

## Vesting Schedule
Polkaswitch Vesting Schedule

Team (15% - 15,000,000 tokens)
Team / Founders - 36 months (1080 days), 1 year cliff

Strategic Advisors (5% - 5,000,000 tokens)
Strategic Advisors - 36 months, 1 year cliff

Private Token Sale (33% - 33,000,000 tokens)
15% unlocked at TGE launch, 20% unlocked at Month 3, 20% unlocked at Month 6, and 45% unlocked at Month 12

Note: Private Token Sale For Hype Partner
25% unlocked at TGE launch, 20% unlocked at Month 3, 20% unlocked at Month 6, and 35% unlocked at Month 12

Exchange Liquidity & Marketing(10% - 10,000,000 tokens)
Exchange Liquidity & Marketing - 35% unlock,  24 months monthly vesting

Development (10% - 10,000,000 tokens)
Development - 15% unlock, 24 months monthly vesting

Community and Liquidity Mining Rewards (27% - 27,000,000 tokens)
Liquidity Mining and Community Incentives, Unlocked

## Deployment
Followed the instruction [here](https://hardhat.org/tutorial/deploying-to-a-live-network.html), I used ether.js to deploy contract.
Uncomment `require("@nomiclabs/hardhat-waffle");` in hardhat.config.js and replace Alchemy and Wallet private key for a given testnet.   
Note: Make sure you get test token from faucet before you deploy your contract.
Run the following command (ropsten as an example):
```
npx hardhat run scripts/deploy.js --network ropsten
```

### Deployed Contract
#### Ropsten
Token: 0x44B2354FB620D364758c88848B120aA0D28e99c7    
Vesting: 0x170446f2dAa16F7f8279a184821c841b6908647c    
Private Vesting: 0x0e29A5c05717524df6DAB0286F9a5E99bd08bf49

## Testing
We use [hardhat](https://hardhat.org/hardhat-network/) to test the contract with local ganache-cli. 

### Steps to test
#### Test SwitchToken Contract
1. First run ganache-cli with chainId (e.g. 1337) and set block time = 1s for auto-mining (one of the test requires sending multiple transactions to one block).
```
ganache-cli --chainId 1337 --blockTime 1
```
2. Run hardhat test with Ganache network
```
npx hardhat --network localhost test test/SwitchToken.test.js
```

#### Test Vesting Contract
I wrote test with Truffle. In hardhat.config.js, uncomment `require("@nomiclabs/hardhat-truffle5");` 

Comment `require("@nomiclabs/hardhat-waffle");` if you just deployed your contract.
1. First run ganache-cli
```
ganache-cli
```
2. Run hardhat test with Ganache network
```
npx hardhat --network localhost test test/Vesting.test.js
```

#### Test Staking Contract
1. First run ganache-cli
```
ganache-cli
```
2. Run hardhat test with Ganache network
```
npx hardhat --network localhost test test/Farming.test.js
```

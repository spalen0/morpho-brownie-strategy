# Yearn Strategy Brownie Mix

## Morpho Strategy

This repo contains a strategy for [Morpho protocol](https://morpho.xyz/) on Ethereum mainnet.
The strategy supplies strategy `want` token to Morpho protocol. If the protocol can find a match from the borrowing side
it connects two sides for a peer-to-peer deal providing [better APY for both sides](https://docs.morpho.xyz/start-here/how-it-works).
Otherwise, the liquidity is supplied to the underlying protocol, Aave or Compound, which provides lower APY.
When a new borrower comes in, he is matched with the highest liquidity supplier.
This flow goes until the full p2p liquidity is matched or all provided gas is used.
See base strategy contract [MorphoStrategy](./contracts/MorphoStrategy.sol).

### Compound

Compound protocol also rewards with additional token COMP which is swapped for strategy `want` token using ySwap.
There is also a fallback option to use Sushi v2 (default) or Uniswap v2 if ySwap is not set.
Except from claiming and swapping reward token, the strategy is the same as base Morpho strategy.
See [MorphoCompoundStrategy](./contracts/MorphoCompoundStrategy.sol).

### Aave

Aave protocol doesn't provide any additional rewards token so Aave strategy just extends the base Morpho strategy.
See [MorphoAaveStrategy](./contracts/MorphoAaveStrategy.sol).

### Want token

The strategy and tests are written for multiple tokens on Morpho protocol: `USDT`, `USDC`, `DAI`, `WETH` and `WBTC`.
The strategy can be easily set to use any token by providing a token address to the strategy constructor.
For more tokens see [Morpho protocol dashboard](https://compound.morpho.xyz/?network=mainnet).

### Tests

There are two strategies and some tests are not the same so they are separated into two folders:

- [aave](./tests/aave/)
- [compound](./tests/compound/)

By default, tests will run for both strategies using `USDT` as want token. To add additional tokens for testing,
expand `token` params list or remove all to disable tests for a specific strategy.

- [aave strategy want token list](./tests/aave/conftest.py#L51)
- [compound strategy want token list](./tests/compound/conftest.py#L52)

### Liquidity data

The liquidity data can be collecting to CSV file using Github Actions Workflow [data.yaml](.github/workflows/data.yaml).
Currently, it's disable, to enable change [workflow job](.github/workflows/data.yaml#L12) and
[set strategy addresses](.github/workflows/data.yaml#L66) that you want to track.
It is scheduled to run [ones per day](.github/workflows/data.yaml#L6).
Workflow supports tracking single and multiple strategies by defining strategy addresses separated by commas.
The liquidity data is appended to a file after each Github Action is completed.

See example of the collected data: [example_file.csv](./data/example_file.csv).
Files for each strategy are created in the [folder data](./data/) with name: `strategy_ADDRESS.csv`.
The data is collected using [Python script](./scripts/write_liquidity.py).

Script for collecting data can be run manually, first define environment variable `STRATEGY_ADDRESSES` in file `.env`.
Run command:

```bash
brownie run scripts/write_liquidity.py
```

### External calls to Morpho

Link to docs for using [IMorpho interface](interfaces/IMorpho.sol):

- [supply](https://developers.morpho.xyz/core-protocol-contracts/morpho/supply)
- [withdraw](https://developers.morpho.xyz/core-protocol-contracts/morpho/withdraw)
- [claimRewards](https://developers.morpho.xyz/core-protocol-contracts/morpho/claimrewards)

[ILens interface](interfaces/lens/ILens.sol) is used to fetch the data from Morpho protocol using just view functions.
Because Morpho uses two different protocols some functions are not the same.
Differing functions are separated per protocol in interface package [lens](interfaces/lens/).
`ILens` has functions that are the same for both protocols:

- [getUserUnclaimedRewards](https://developers.morpho.xyz/lens#getuserunclaimedrewards)
- [getCurrentSupplyBalanceInOf](https://developers.morpho.xyz/lens#getcurrentsupplybalanceinof)
- [getMainMarketData](https://developers.morpho.xyz/lens#getmainmarketdata)

#### MORPHO rewards

Morpho protocol also provides its own rewards tokens: `$MORPHO`. Rewards can be claimed by providing Merkle proof.
For more info see [Morpho docs](https://developers.morpho.xyz/core-protocol-contracts/rewardsdistributor).
On how to claim rewards check out function [claimMorphoRewards](contracts/MorphoStrategy.sol#L229).
Morpho token still doesn't have a pair for trading but it's added to ySwap for future swapping to want token.

## Installation and Setup

1. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) & [Ganache](https://github.com/trufflesuite/ganache), if you haven't already. Make sure that the version of Ganache that you install is compatible with Brownie. You can check Brownie's Ganache dependency [here](https://eth-brownie.readthedocs.io/en/stable/install.html#dependencies).

2. Sign up for [Infura](https://infura.io/) and generate an API key. Store it in the `WEB3_INFURA_PROJECT_ID` environment variable.

```bash
export WEB3_INFURA_PROJECT_ID=YourProjectID
```

3. Sign up for [Etherscan](www.etherscan.io) and generate an API key. This is required for fetching source codes of the mainnet contracts we will be interacting with. Store the API key in the `ETHERSCAN_TOKEN` environment variable.

```bash
export ETHERSCAN_TOKEN=YourApiToken
```

- Optional Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETHERSCAN_TOKEN` and `WEB3_INFURA_PROJECT_ID`
     NOTE: If you set up a global environment variable, that will take precedence

4. Download the mix.

```bash
brownie bake yearn-strategy
```

## Basic Use

To deploy the demo Yearn Strategy in a development environment:

1. Open the Brownie console. This automatically launches Ganache on a forked mainnet.

```bash
brownie console
```

2. Create variables for the Yearn Vault and Want Token addresses. These were obtained from the Yearn Registry. We load them from a different repository found in the brownie-config.yml under dependencies (yearn/yearn-vaults@0.4.3):

```python
from brownie import project
yearnvaults = project.load(config["dependencies"][0]) #load the base vaults project to access the original Vault contract
Vault = yearnvaults.Vault
Token = yearnvaults.Token
vault = Vault.at("0xdA816459F1AB5631232FE5e97a05BBBb94970c95")
token = Token.at("0x6b175474e89094c44da98b954eedeac495271d0f")
gov = "ychad.eth"  # ENS for Yearn Governance Multisig
```

or you can get the contracts ABI from etherscan API, make sure you have exported your etherscan token.

```python
from brownie import Contract
vault = Contract("0xdA816459F1AB5631232FE5e97a05BBBb94970c95")
token = Contract("0x6b175474e89094c44da98b954eedeac495271d0f")
gov = "ychad.eth"  # ENS for Yearn Governance Multisig
```

3. Deploy the [`Strategy.sol`](contracts/Strategy.sol) contract.

```python
>>> strategy = Strategy.deploy(vault, {"from": accounts[0]})
Transaction sent: 0xc8a35b3ecbbed196a344ed6b5c7ee6f50faf9b7eee836044d1c7ffe10093ef45
  Gas price: 0.0 gwei   Gas limit: 6721975
  Flashloan.constructor confirmed - Block: 9995378   Gas used: 796934 (11.86%)
  Flashloan deployed at: 0x3194cBDC3dbcd3E11a07892e7bA5c3394048Cc87
```

4. Approve the strategy for the Vault. We must do this because we only approved Strategies can pull funding from the Vault.

```python
# 10% of the vault tokens will be allocated to the strategy

>>> vault.addStrategy(strategy, 1000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
Transaction sent: 0xa70b90eb9a9899e8f6e709c53a436976315b4279c4b6797d0a293e169f94d5b4
  Gas price: 0.0 gwei   Gas limit: 6721975
  Transaction confirmed - Block: 9995379   Gas used: 21055 (0.31%)
```

If you are getting a revert error, it's most likley because the vault can't add more strategies, you can check the `vault.debtRatio()` the value should be under 10,000. You can try to lower one of the existing strategy debt ratio `vault.updateStrategyDebtRatio("0x1676055fE954EE6fc388F9096210E5EbE0A9070c", 0, {"from": gov})`

5. Now we are ready to put our strategy into action!

```python
>>> harvest_tx = strategy.harvest({"from": accounts[0]})  # perform as many time as desired...
```

## Implementing Strategy Logic

[`contracts/Strategy.sol`](contracts/Strategy.sol) is where you implement your own logic for your strategy. In particular:

- Create a descriptive name for your strategy via `Strategy.name()`.
- Invest your want tokens via `Strategy.adjustPosition()`.
- Take profits and report losses via `Strategy.prepareReturn()`.
- Unwind enough of your position to payback withdrawals via `Strategy.liquidatePosition()`.
- Unwind all of your positions via `Strategy.exitPosition()`.
- Fill in a way to estimate the total `want` tokens managed by the strategy via `Strategy.estimatedTotalAssets()`.
- Migrate all the positions managed by your strategy via `Strategy.prepareMigration()`.
- Make a list of all position tokens that should be protected against movements via `Strategy.protectedTokens()`.

## Testing

To run the tests:

```bash
brownie test
```

The example tests provided in this mix start by deploying and approving your [`Strategy.sol`](contracts/Strategy.sol) contract. This ensures that the loan executes succesfully without any custom logic. Once you have built your own logic, you should edit [`tests/test_flashloan.py`](tests/test_flashloan.py) and remove this initial funding logic.

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/tests-pytest-intro.html) for more detailed information on testing your project.

## Debugging Failed Transactions

Use the `--interactive` flag to open a console immediatly after each failing test:

```
brownie test --interactive
```

Within the console, transaction data is available in the [`history`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#txhistory) container:

```python
>>> history
[<Transaction '0x50f41e2a3c3f44e5d57ae294a8f872f7b97de0cb79b2a4f43cf9f2b6bac61fb4'>,
 <Transaction '0xb05a87885790b579982983e7079d811c1e269b2c678d99ecb0a3a5104a666138'>]
```

Examine the [`TransactionReceipt`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#transactionreceipt) for the failed test to determine what went wrong. For example, to view a traceback:

```python
>>> tx = history[-1]
>>> tx.traceback()
```

To view a tree map of how the transaction executed:

```python
>>> tx.call_trace()
```

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/core-transactions.html) for more detailed information on debugging failed transactions.

<!--
## Deployment

When you are finished testing and ready to deploy to the mainnet:

1. [Import a keystore](https://eth-brownie.readthedocs.io/en/stable/account-management.html#importing-from-a-private-key) into Brownie for the account you wish to deploy from.
2. Edit [`scripts/deployment.py`](scripts/deployment.py) and add your keystore ID according to the comments.
3. Run the deployment script on the mainnet using the following command:

```bash
$ brownie run deployment --network mainnet
```

You will be prompted to enter your keystore password, and then the contract will be deployed.
-->

## Known issues

### No access to archive state errors

If you are using Ganache to fork a network, then you may have issues with the blockchain archive state every 30 minutes. This is due to your node provider (i.e. Infura) only allowing free users access to 30 minutes of archive state. To solve this, upgrade to a paid plan, or simply restart your ganache instance and redeploy your contracts.

## Resources

- Yearn [Discord channel](https://discord.com/invite/6PNv2nF/)
- Brownie [Gitter channel](https://gitter.im/eth-brownie/community)

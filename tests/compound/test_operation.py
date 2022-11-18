import brownie
from brownie import Contract
import pytest


def test_operation(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # tend()
    strategy.tend()

    # withdrawal
    vault.withdraw({"from": user})
    assert (
        pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )


def test_emergency_exit(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # set emergency and exit
    strategy.setEmergencyExit()
    chain.sleep(1)
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < amount


def test_profitable_harvest(
    chain,
    accounts,
    token,
    vault,
    strategy,
    user,
    strategist,
    gov,
    amount,
    RELATIVE_APPROX,
    comp_token,
    comp_whale,
):
    # Disable trade factory so strategy can swap reward tokens to want tokens using sushiswap as fallback option
    strategy.removeTradeFactoryPermissions({"from": gov})

    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    before_pps = vault.pricePerShare()

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # Strategy earned reward tokens
    comp_token.transfer(
        strategy, 2 * strategy.minCompToClaimOrSell(), {"from": comp_whale}
    )

    # Harvest 2: Realize profit
    chain.sleep(1)
    strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = token.balanceOf(vault.address)  # Profits go to vault
    assert strategy.estimatedTotalAssets() + profit > amount
    assert vault.pricePerShare() > before_pps


def test_change_debt(
    chain, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    half = int(amount / 2)

    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half

    vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # In order to pass this tests, you will need to implement prepareReturn.
    # TODO: uncomment the following lines.
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == half


def test_sweep(
    gov,
    vault,
    strategy,
    token,
    user,
    amount,
    weth,
    weth_amount,
    usdt,
    usdt_amount,
    pool_token,
    comp_token,
    comp_whale,
):
    # Strategy want token doesn't work
    token.transfer(strategy, amount, {"from": user})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})

    # TODO: If you add protected tokens to the strategy.
    # Protected token doesn't work
    # with brownie.reverts("!protected"):
    #     strategy.sweep(strategy.protectedToken(), {"from": gov})

    comp_amount = 2 * strategy.minCompToClaimOrSell()
    comp_token.transfer(strategy, comp_amount, {"from": comp_whale})

    if weth.address != strategy.want():
        before_balance = weth.balanceOf(gov)
        weth.transfer(strategy, weth_amount, {"from": user})
        assert weth.address != strategy.want()
        assert weth.balanceOf(user) == 0
        strategy.sweep(weth, {"from": gov})
        assert weth.balanceOf(gov) == weth_amount + before_balance
    else:
        before_balance = usdt.balanceOf(gov)
        usdt.transfer(strategy, usdt_amount, {"from": user})
        assert usdt.address != strategy.want()
        assert usdt.balanceOf(user) == 0
        strategy.sweep(usdt, {"from": gov})
        assert usdt.balanceOf(gov) == usdt_amount + before_balance

    # protected token shouldn't be sweeped
    assert comp_token.balanceOf(strategy) == comp_amount


def test_triggers(
    chain, gov, vault, strategy, token, amount, user, weth, weth_amount, strategist
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()

    strategy.harvestTrigger(0)
    strategy.tendTrigger(0)

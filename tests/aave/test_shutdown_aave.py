# TODO: Add tests that show proper operation of this strategy through "emergencyExit"
#       Make sure to demonstrate the "worst case losses" as well as the time it takes

from brownie import ZERO_ADDRESS
import pytest


def test_vault_shutdown_can_withdraw(
    chain, token, vault, strategy, user, amount, RELATIVE_APPROX, token_whale
):
    ## Deposit in Vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    if token.balanceOf(user) > 0:
        # token.transfer(ZERO_ADDRESS, token.balanceOf(user), {"from": user})
        token.transfer(token_whale, token.balanceOf(user), {"from": user})

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    chain.mine(1)
    tx = strategy.harvest()
    chain.sleep(3600 * 7)
    chain.mine(1)
    # assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount
    assert strategy.estimatedTotalAssets() >= amount

    ## Set Emergency
    vault.setEmergencyShutdown(True)

    ## Withdraw (does it work, do you get what you expect)
    vault.withdraw({"from": user})

    # assert pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX) == amount
    assert token.balanceOf(user) >= amount


def test_basic_shutdown(
    chain, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    chain.mine(1)
    tx = strategy.harvest()
    chain.mine(100)
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    ## Earn interest
    chain.sleep(3600 * 24 * 1)  ## Sleep 1 day
    chain.mine(1)

    # Harvest 2: Realize profit
    tx = strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)

    ## Set emergency
    strategy.setEmergencyExit({"from": strategist})

    tx = strategy.harvest()  ## Remove funds from strategy

    assert token.balanceOf(strategy) == 0
    ## The vault has all funds
    # assert (pytest.approx(token.balanceOf(vault), rel=RELATIVE_APPROX) == amount)
    assert token.balanceOf(vault) >= amount
    ## NOTE: May want to tweak this based on potential loss during migration

import brownie
from brownie import Contract, Wei, reverts, ZERO_ADDRESS
import pytest


def test_strategy_setup(token, strategy, trade_factory, morpho_token):
    assert token.allowance(strategy.address, strategy.morpho()) == 2**256 - 1
    assert (
        morpho_token.allowance(strategy.address, trade_factory.address) == 2**96 - 1
    )


def test_set_max_gas_for_matching(strategy):
    assert strategy.maxGasForMatching() == 100000
    new_value = Wei("0.05212 ether")
    strategy.setMaxGasForMatching(new_value)
    assert strategy.maxGasForMatching() == new_value


def test_set_rewards_distributor(strategy, rando):
    assert strategy.rewardsDistributor() == "0x3B14E5C73e0A56D607A8688098326fD4b4292135"

    with reverts():
        strategy.setRewardsDistributor(strategy, {"from": rando})

    strategy.setRewardsDistributor(ZERO_ADDRESS)
    assert strategy.rewardsDistributor() == ZERO_ADDRESS

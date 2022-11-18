import brownie
from brownie import ZERO_ADDRESS
import pytest


def test_disabling_trade_factory(strategy, gov, trade_factory, morpho_token):
    assert strategy.tradeFactory() == trade_factory.address
    assert (
        morpho_token.allowance(strategy.address, trade_factory.address) == 2**96 - 1
    )
    strategy.removeTradeFactoryPermissions({"from": gov})
    assert strategy.tradeFactory() == ZERO_ADDRESS
    assert morpho_token.allowance(strategy.address, trade_factory.address) == 0

import pytest
from brownie import MockStrategy
from utils import *


@pytest.fixture(scope="function")
def primary_strategy(admin, gro_vault, bot, next_strategy):
    primary_strategy = next_strategy()
    gro_vault.addStrategy(primary_strategy.address, 5000, {"from": admin})
    return primary_strategy


@pytest.fixture(scope="function")
def secondary_strategy(admin, gro_vault, bot, next_strategy):
    secondary_strategy = next_strategy()
    gro_vault.addStrategy(secondary_strategy.address, 5000, {"from": admin})
    return secondary_strategy


@pytest.fixture(scope="function")
def primary_mock_strategy(admin, mock_gro_vault_usdc, bot, next_mock_strategy):
    _strategy = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(_strategy.address, 5000, {"from": admin})
    return _strategy


@pytest.fixture(scope="function")
def secondary_mock_strategy(admin, mock_gro_vault_usdc, bot, next_mock_strategy):
    _strategy = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(_strategy.address, 5000, {"from": admin})
    return _strategy


@pytest.fixture(scope="function")
def fill_queue(admin, mock_gro_vault_usdc, bot, next_mock_strategy):
    strategy_queue = []
    for i in range(5):
        strategy = next_mock_strategy()
        mock_gro_vault_usdc.addStrategy(strategy.address, 1000, {"from": admin})
        strategy_queue.append(strategy)
    return strategy_queue


@pytest.fixture(scope="function")
def next_strategy(admin, gro_vault, bot):
    generator = strategy_generator(admin, gro_vault, bot)

    def get_strategy():
        return next(generator)

    return get_strategy


@pytest.fixture(scope="function")
def next_mock_strategy(admin, mock_gro_vault_usdc, bot):
    generator = strategy_generator(admin, mock_gro_vault_usdc, bot)

    def get_strategy():
        return next(generator)

    return get_strategy


def strategy_generator(admin, gro_vault, bot):
    while True:
        strategy = admin.deploy(MockStrategy, gro_vault.address)
        strategy.setKeeper(bot, {"from": admin})
        yield strategy

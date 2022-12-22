import pytest
from brownie import GTrancheGeneric
from conftest import *


@pytest.fixture(scope="function", autouse=True)
def new_gTokens(accounts):
    senior = accounts[0].deploy(SeniorTranche, "senior", "snr")
    junior = accounts[0].deploy(JuniorTranche, "junior", "jnr")
    return [junior, senior]


@pytest.fixture(scope="function", autouse=True)
def old_tranche(accounts, tokens, new_gTokens, mockOracle):
    old_tranche = accounts[0].deploy(
        GTrancheGeneric, tokens, new_gTokens, mockOracle, ZERO_ADDRESS
    )
    new_gTokens[0].setController(old_tranche.address, {"from": accounts[0]})
    new_gTokens[0].addToWhitelist(old_tranche.address, {"from": accounts[0]})
    new_gTokens[1].setController(old_tranche.address, {"from": accounts[0]})
    new_gTokens[1].addToWhitelist(old_tranche.address, {"from": accounts[0]})
    return old_tranche


@pytest.fixture(scope="function", autouse=True)
def new_tranche(accounts, tokens, new_gTokens, mockOracle):
    new_tranche = accounts[0].deploy(
        GTrancheGeneric, tokens, new_gTokens, mockOracle, ZERO_ADDRESS
    )
    new_gTokens[0].setController(new_tranche.address, {"from": accounts[0]})
    new_gTokens[0].addToWhitelist(new_tranche.address, {"from": accounts[0]})
    new_gTokens[1].setController(new_tranche.address, {"from": accounts[0]})
    new_gTokens[1].addToWhitelist(new_tranche.address, {"from": accounts[0]})
    return new_tranche


# given when the gtranche is setup with one token using the mainnet setup
# can we correctly setup the tranche with the old 4626 token and
def test_migrate_from_gtranche_to_gtranche(users, old_tranche, tokens, new_tranche):
    setup_tranche_all_tokens(tokens, LARGE_NUMBER, users, old_tranche)
    old_tranche_junior_balance = old_tranche.trancheBalances(False)
    old_tranche_senior_balance = old_tranche.trancheBalances(True)
    old_tranche_token_balance_0 = old_tranche.tokenBalances(0)
    old_tranche_token_balance_1 = old_tranche.tokenBalances(1)
    old_tranche_token_balance_2 = old_tranche.tokenBalances(2)
    # max approve yield tokens for new tranche - incase more tokens get added
    old_tranche.prepareMigration(new_tranche.address, {"from": accounts[0]})
    # loop over each yield token and
    # read yield token balances and update the balance and assert its the same address
    # read tranche junior and senior balance and add to the current balance
    # (assumes same denominator) transfer yield tokens over and
    # updates state of old tranche
    new_tranche.migrate(old_tranche.address, {"from": accounts[0]})

    new_tranche_junior_balance = new_tranche.trancheBalances(False)
    new_tranche_senior_balance = new_tranche.trancheBalances(True)
    new_tranche_token_balance_0 = new_tranche.tokenBalances(0)
    new_tranche_token_balance_1 = new_tranche.tokenBalances(1)
    new_tranche_token_balance_2 = new_tranche.tokenBalances(2)
    assert new_tranche_junior_balance >= old_tranche_junior_balance
    assert new_tranche_senior_balance >= old_tranche_senior_balance
    assert new_tranche_token_balance_0 >= old_tranche_token_balance_0
    assert new_tranche_token_balance_1 >= old_tranche_token_balance_1
    assert new_tranche_token_balance_2 >= old_tranche_token_balance_2
    assert old_tranche.trancheBalances(False) == 0
    assert old_tranche.trancheBalances(True) == 0
    assert old_tranche.tokenBalances(0) == 0
    assert old_tranche.tokenBalances(0) == 0
    assert old_tranche.tokenBalances(0) == 0

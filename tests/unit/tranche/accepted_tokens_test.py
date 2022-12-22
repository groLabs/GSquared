import pytest
from brownie import exceptions
from conftest import *


def test_tranche_setup(admin, tranche, tokens, gTokens):
    assert tranche.getYieldToken(0) == tokens[0]
    assert tranche.getTrancheToken(JUNIOR_TRANCHE) == gTokens[0]
    assert tranche.getTrancheToken(SENIOR_TRANCHE) == gTokens[1]


def setup_token(token, amount, user, tranche):
    token.mint(user.address, amount, {"from": user.address})
    token.approve(tranche.address, LARGE_NUMBER, {"from": user.address})
    token.setTotalAssets(amount)


def test_deposit_registered_token(admin, user_1, tranche, tokens):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    tranche.deposit(
        LARGE_NUMBER,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert tokens[token_index].balanceOf(user_1.address) == 0
    assert tokens[token_index].balanceOf(tranche.address) == LARGE_NUMBER
    assert tranche.tokenBalances(token_index) == LARGE_NUMBER


def test_deposit_unregistered_token(admin, user_1, tranche, tokens):
    token_index = 1
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    with pytest.raises(exceptions.VirtualMachineError):
        tranche.deposit(
            LARGE_NUMBER,
            token_index,
            JUNIOR_TRANCHE,
            user_1.address,
            {"from": user_1.address},
        )
    assert tokens[token_index].balanceOf(user_1.address) == LARGE_NUMBER
    assert tokens[token_index].balanceOf(tranche.address) == 0


def test_withdraw_registered_token(admin, user_1, tranche, tokens, gTokens):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    tranche.deposit(
        LARGE_NUMBER,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    tranche.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address),
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert tokens[token_index].balanceOf(user_1.address) == LARGE_NUMBER
    assert tokens[token_index].balanceOf(tranche.address) == 0
    assert tranche.tokenBalances(token_index) == 0


def test_withdraw_unregistered_token(admin, user_1, tranche, tokens):
    token_index = 1
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    with pytest.raises(exceptions.VirtualMachineError):
        tranche.deposit(
            LARGE_NUMBER,
            token_index,
            JUNIOR_TRANCHE,
            user_1.address,
            {"from": user_1.address},
        )
    assert tokens[token_index].balanceOf(user_1.address) == LARGE_NUMBER
    assert tokens[token_index].balanceOf(tranche.address) == 0


def test_get_senior_tranche_tokens_on_deposit(admin, user_1, tranche, tokens, gTokens):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    assert gTokens[SENIOR_TRANCHE].balanceOf(user_1.address) == 0
    tranche.deposit(
        LARGE_NUMBER / 2,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    tranche.deposit(
        LARGE_NUMBER / 4,
        token_index,
        SENIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[SENIOR_TRANCHE].balanceOf(user_1.address) > 0


def test_get_junior_tranche_tokens_on_deposit(admin, user_1, tranche, tokens, gTokens):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    assert gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address) == 0
    tranche.deposit(
        LARGE_NUMBER,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address) > 0


def test_burn_senior_tranche_tokens_on_withdrawal(
    admin, user_1, tranche, tokens, gTokens
):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    tranche.deposit(
        LARGE_NUMBER / 2,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    tranche.deposit(
        LARGE_NUMBER / 4,
        token_index,
        SENIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[SENIOR_TRANCHE].balanceOf(user_1.address) > 0
    tranche.withdraw(
        gTokens[SENIOR_TRANCHE].balanceOf(user_1.address),
        token_index,
        SENIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[SENIOR_TRANCHE].balanceOf(user_1.address) == 0


def test_burn_junior_tranche_tokens_on_withdrawal(
    admin, user_1, tranche, tokens, gTokens
):
    token_index = 0
    setup_token(tokens[token_index], LARGE_NUMBER, user_1, tranche)
    tranche.deposit(
        LARGE_NUMBER,
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address) > 0
    tranche.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address),
        token_index,
        JUNIOR_TRANCHE,
        user_1.address,
        {"from": user_1.address},
    )
    assert gTokens[JUNIOR_TRANCHE].balanceOf(user_1.address) == 0

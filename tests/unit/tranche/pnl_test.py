import math

import pytest
from brownie import exceptions
from conftest import *


def test_pnl_asset_distribution(admin, users, tranche, tokens):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    assert tranche.tokenBalances(0) > 0


def test_deposit_works_within_utilzation_ratio_limit(admin, users, tranche, tokens):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert (
        tranche.trancheBalances(SENIOR_TRANCHE)
        / tranche.trancheBalances(JUNIOR_TRANCHE)
        <= 0.5
    )


def test_deposit_fails_outside_utilzation_ratio_limit(admin, users, tranche, tokens):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 3, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    with pytest.raises(exceptions.VirtualMachineError):
        tranche.deposit(
            _amount / 2,
            token_index,
            SENIOR_TRANCHE,
            user.address,
            {"from": user.address},
        )
    assert (
        tranche.trancheBalances(SENIOR_TRANCHE)
        / tranche.trancheBalances(JUNIOR_TRANCHE)
        == 0
    )


def test_withdrawals_works_within_utilzation_ratio_limit(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_utilization_ratio = tranche.trancheBalances(
        SENIOR_TRANCHE
    ) / tranche.trancheBalances(JUNIOR_TRANCHE)
    assert initial_utilization_ratio <= 1.0
    tranche.withdraw(
        gTokens[JUNIOR_TRANCHE_ID].balanceOf(user.address) / 5,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert (
        tranche.trancheBalances(SENIOR_TRANCHE)
        / tranche.trancheBalances(JUNIOR_TRANCHE)
        > initial_utilization_ratio
    )


def test_withdrawals_fails_outside_utilzation_ratio_limit(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 3, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_utilization_ratio = tranche.trancheBalances(
        SENIOR_TRANCHE
    ) / tranche.trancheBalances(JUNIOR_TRANCHE)
    assert initial_utilization_ratio <= 1.0
    with pytest.raises(exceptions.VirtualMachineError):
        tranche.withdraw(
            gTokens[JUNIOR_TRANCHE_ID].balanceOf(user.address) / 2,
            token_index,
            JUNIOR_TRANCHE,
            user.address,
            {"from": user.address},
        )
    assert (
        tranche.trancheBalances(SENIOR_TRANCHE)
        / tranche.trancheBalances(JUNIOR_TRANCHE)
        == initial_utilization_ratio
    )


def test_senior_tranche_asserts_increase_on_deposit(admin, users, tranche, tokens):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    assert tranche.trancheBalances(JUNIOR_TRANCHE) == 0
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche.trancheBalances(JUNIOR_TRANCHE) > 0


def test_senior_tranche_asserts_decrease_on_withdrawal(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    assert tranche.trancheBalances(JUNIOR_TRANCHE) == 0
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_ST_assets = tranche.trancheBalances(SENIOR_TRANCHE)
    tranche.withdraw(
        gTokens[SENIOR_TRANCHE_ID].balanceOf(user.address) / 2,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert math.isclose(tranche.trancheBalances(SENIOR_TRANCHE), initial_ST_assets / 2)


def test_junior_tranche_asserts_increase_on_deposit(admin, users, tranche, tokens):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    assert tranche.trancheBalances(JUNIOR_TRANCHE) == 0
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche.trancheBalances(JUNIOR_TRANCHE) > 0


def test_junior_tranche_asserts_decrease_on_withdrawal(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_JT_assets = tranche.trancheBalances(JUNIOR_TRANCHE)
    tranche.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user.address) / 2,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert math.isclose(tranche.trancheBalances(JUNIOR_TRANCHE), initial_JT_assets / 2)


def test_utilization_increases_on_minting_of_senior_tranche_token(
    admin, users, tranche, tokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche.utilization()
    assert initial_U_ratio > 0
    tranche.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche.utilization() > initial_U_ratio


def test_utilization_decreases_on_burning_of_senior_tranche_token(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche.utilization()
    assert initial_U_ratio > 0
    tranche.withdraw(
        gTokens[SENIOR_TRANCHE_ID].balanceOf(user.address) / 8,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert tranche.utilization() < initial_U_ratio


def test_utilization_decreases_on_minting_of_junior_tranche_token(
    admin, users, tranche, tokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche.utilization()
    assert initial_U_ratio > 0
    tranche.deposit(
        _amount / 8, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche.utilization() < initial_U_ratio


def test_utilization_increases_on_burning_of_junior_tranche_token(
    admin, users, tranche, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche)
    tranche.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche.utilization()
    assert initial_U_ratio > 0
    tranche.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user.address) / 8,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert tranche.utilization() > initial_U_ratio


def test_profit_distribution_curve(admin, users, tranche, tokens):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets * 2)
    final_tranche_token_assets = tranche.pnlDistribution()[0]
    assert initial_tranche_token_assets[0] < final_tranche_token_assets[0]
    assert initial_tranche_token_assets[1] < final_tranche_token_assets[1]
    assert (
        final_tranche_token_assets[0] - initial_tranche_token_assets[0]
        > final_tranche_token_assets[1] - initial_tranche_token_assets[1]
    )


def test_asset_loss_handling_should_first_impact_the_junior_tranche(
    admin, users, tranche, tokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 2)
    final_tranche_token_assets = tranche.pnlDistribution()[0]
    assert initial_tranche_token_assets[0] > final_tranche_token_assets[0]
    assert initial_tranche_token_assets[1] == final_tranche_token_assets[1]


def test_senior_tranche_should_only_be_affected_after_junior_is_empty(
    admin, users, tranche, tokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 3)
    first_loss_tranche_token_assets = tranche.pnlDistribution()[0]
    # loss should have been absorbed by junior tranche
    assert first_loss_tranche_token_assets[0] < 1e14  # small amount left
    assert initial_tranche_token_assets[1] == first_loss_tranche_token_assets[1]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets - 1e18)
    final_tranche_token_assets = tranche.pnlDistribution()[0]
    # loss should now exist on both tranches
    assert final_tranche_token_assets[0] == 0
    assert initial_tranche_token_assets[1] > final_tranche_token_assets[1]


def test_gains_after_loss_should_repay_junior_tranche_first(
    admin, users, tranche, get_pnl, tokens
):
    token_index = 0
    user = users[0]
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 3)
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    first_loss_tranche_token_assets = tranche.pnlDistribution()[0]
    # loss should have been absorbed by junior tranche
    assert first_loss_tranche_token_assets[0] < 1e14  # small amount left
    assert initial_tranche_token_assets[1] == first_loss_tranche_token_assets[1] + 1
    assert get_pnl.juniorLoss() > 0
    tokens[0].setTotalAssets(token_assets)  # revert to start
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    regain_tranche_token_assets = tranche.pnlDistribution()[0]
    # gains should only exist in junior tranche (junior loss == 0)
    # rounding error in the diff?
    assert abs(regain_tranche_token_assets[0] - initial_tranche_token_assets[0]) <= 1
    assert initial_tranche_token_assets[1] == regain_tranche_token_assets[1] + 2
    # rounding error in the diff?
    assert get_pnl.juniorLoss() <= 1

    tokens[0].setTotalAssets(token_assets + 10000 * 10**18)  # gainz
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    profit_tranche_token_assets = tranche.pnlDistribution()[0]
    assert regain_tranche_token_assets[0] < profit_tranche_token_assets[0]
    assert regain_tranche_token_assets[1] < profit_tranche_token_assets[1]
    assert (profit_tranche_token_assets[0] - regain_tranche_token_assets[0]) > (
        profit_tranche_token_assets[1] + 1 - regain_tranche_token_assets[1]
    )
    assert get_pnl.juniorLoss() == 0


def test_gains_after_loss_should_repay_junior_tranche_first_again(
    admin, users, tranche, get_pnl, tokens
):
    token_index = 0
    user = users[0]
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets - token_assets / 5)
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert get_pnl.juniorLoss() > 0
    tokens[0].setTotalAssets(token_assets + 2 * (token_assets / 5))  # gainz
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    regain_tranche_token_assets = tranche.pnlDistribution()[0]
    # gains should only exist in junior tranche (junior loss == 0)
    # rounding error in the diff?
    assert regain_tranche_token_assets[0] > initial_tranche_token_assets[0]
    assert regain_tranche_token_assets[1] + 2 > initial_tranche_token_assets[1]
    # rounding error in the diff?
    assert get_pnl.juniorLoss() == 0
    assert (regain_tranche_token_assets[0] - initial_tranche_token_assets[0]) > (
        regain_tranche_token_assets[1] - initial_tranche_token_assets[1] + 2
    )
    # Should really be another test here => regain_tranche_token_assets[0] -
    # initial_tranche_token_assets[0] == juniorLoss + pnl(profit - juniorLoss)


def test_it_should_be_possible_to_reset_junior_debt(
    admin, users, tranche, get_pnl, tokens
):
    token_index = 0
    user = users[0]
    setup_tranche(tokens, LARGE_NUMBER, users, tranche)
    initial_tranche_token_assets = tranche.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 3)
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    first_loss_tranche_token_assets = tranche.pnlDistribution()[0]
    # loss should have been absorbed by junior tranche
    assert first_loss_tranche_token_assets[0] < 1e14  # small amount left
    assert initial_tranche_token_assets[1] == first_loss_tranche_token_assets[1] + 1
    assert get_pnl.juniorLoss() > 0
    tokens[0].setTotalAssets(
        token_assets - token_assets / 5
    )  # return some of the losses
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    regain_tranche_token_assets = tranche.pnlDistribution()[0]
    # gains should only exist in junior tranche (junior loss > 0)
    # rounding error in the diff?
    assert abs(regain_tranche_token_assets[0] - initial_tranche_token_assets[0]) > 1
    assert initial_tranche_token_assets[1] == regain_tranche_token_assets[1] + 2
    # rounding error in the diff?
    assert get_pnl.juniorLoss() > 1

    get_pnl.resetJuniorDebt({"from": admin})
    tokens[0].setTotalAssets(token_assets)  # return to init value
    tranche.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    profit_tranche_token_assets = tranche.pnlDistribution()[0]
    assert regain_tranche_token_assets[0] < profit_tranche_token_assets[0]
    assert regain_tranche_token_assets[1] < profit_tranche_token_assets[1] + 3
    # rounding error in the diff?
    assert get_pnl.juniorLoss() == 0

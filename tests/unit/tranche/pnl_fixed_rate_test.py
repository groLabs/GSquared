import math

import pytest
from brownie import exceptions
from conftest import *


def test_pnl_asset_distribution(admin, users, tranche_fixed_rate, tokens):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    assert tranche_fixed_rate.tokenBalances(0) > 0


def test_deposit_works_within_utilzation_ratio_limit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert (
        gTokens[1].trancheBalance() / gTokens[0].trancheBalance()
        <= 0.5
    )


def test_deposit_fails_outside_utilzation_ratio_limit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 3, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    with pytest.raises(exceptions.VirtualMachineError):
        tranche_fixed_rate.deposit(
            _amount / 2,
            token_index,
            SENIOR_TRANCHE,
            user.address,
            {"from": user.address},
        )
    assert (
        gTokens[1].trancheBalance() / gTokens[0].trancheBalance() == 0
    )


def test_withdrawals_works_within_utilzation_ratio_limit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_utilisation_ratio = gTokens[1].trancheBalance() / gTokens[0].trancheBalance()
    assert initial_utilisation_ratio <= 0.5
    tranche_fixed_rate.withdraw(
        gTokens[JUNIOR_TRANCHE_ID].balanceOf(user.address) / 5,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert (
        gTokens[1].trancheBalance() / gTokens[0].trancheBalance() > initial_utilisation_ratio
    )


def test_withdrawals_fails_outside_utilzation_ratio_limit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_utilisation_ratio = gTokens[1].trancheBalance() / gTokens[0].trancheBalance()
    assert initial_utilisation_ratio <= 1.0
    with pytest.raises(exceptions.VirtualMachineError):
        tranche_fixed_rate.withdraw(
            gTokens[JUNIOR_TRANCHE_ID].balanceOf(user.address) / 5,
            token_index,
            JUNIOR_TRANCHE,
            user.address,
            {"from": user.address},
        )
    assert (gTokens[1].trancheBalance() / gTokens[0].trancheBalance() == initial_utilisation_ratio)


def test_senior_tranche_asserts_increase_on_deposit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    assert gTokens[0].trancheBalance() == 0
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert gTokens[0].trancheBalance() > 0


def test_senior_tranche_asserts_decrease_on_withdrawal(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    assert gTokens[0].trancheBalance() == 0
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_ST_assets = gTokens[1].trancheBalance()
    tranche_fixed_rate.withdraw(
        gTokens[SENIOR_TRANCHE_ID].balanceOf(user.address) / 2,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert math.isclose(
        gTokens[1].trancheBalance() / (initial_ST_assets / 2),
        1,
        abs_tol=0.000001,
    )


def test_junior_tranche_asserts_increase_on_deposit(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    assert gTokens[0].trancheBalance() == 0
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert gTokens[0].trancheBalance() > 0


def test_junior_tranche_asserts_decrease_on_withdrawal(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_JT_assets = gTokens[0].trancheBalance()
    tranche_fixed_rate.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user.address) / 2,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert math.isclose(
        gTokens[0].trancheBalance() / (initial_JT_assets / 2),
        1,
        abs_tol=0.000001,
    )


def test_utilisation_increases_on_minting_of_senior_tranche_token(
    admin, users, tranche_fixed_rate, tokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche_fixed_rate.utilisation()
    assert initial_U_ratio > 0
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche_fixed_rate.utilisation() > initial_U_ratio


def test_utilisation_decreases_on_burning_of_senior_tranche_token(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 4, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche_fixed_rate.utilisation()
    assert initial_U_ratio > 0
    tranche_fixed_rate.withdraw(
        gTokens[SENIOR_TRANCHE_ID].balanceOf(user.address) / 8,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert tranche_fixed_rate.utilisation() < initial_U_ratio


def test_utilisation_decreases_on_minting_of_junior_tranche_token(
    admin, users, tranche_fixed_rate, tokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche_fixed_rate.utilisation()
    assert initial_U_ratio > 0
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    assert tranche_fixed_rate.utilisation() < initial_U_ratio


def test_utilisation_increases_on_burning_of_junior_tranche_token(
    admin, users, tranche_fixed_rate, tokens, gTokens
):
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    tranche_fixed_rate.deposit(
        _amount / 2, token_index, JUNIOR_TRANCHE, user.address, {"from": user.address}
    )
    tranche_fixed_rate.deposit(
        _amount / 8, token_index, SENIOR_TRANCHE, user.address, {"from": user.address}
    )
    initial_U_ratio = tranche_fixed_rate.utilisation()
    assert initial_U_ratio > 0
    tranche_fixed_rate.withdraw(
        gTokens[JUNIOR_TRANCHE].balanceOf(user.address) / 8,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    assert tranche_fixed_rate.utilisation() > initial_U_ratio


def test_profit_distribution_curve(admin, users, tranche_fixed_rate, tokens):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets * 2)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert initial_tranche_token_assets[0] < final_tranche_token_assets[0]
    assert initial_tranche_token_assets[1] < final_tranche_token_assets[1]
    assert (
        final_tranche_token_assets[0] - initial_tranche_token_assets[0]
        > final_tranche_token_assets[1] - initial_tranche_token_assets[1]
    )


def test_asset_loss_handling_should_first_impact_the_junior_tranche(
    admin, users, tranche_fixed_rate, tokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 2)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert initial_tranche_token_assets[0] > final_tranche_token_assets[0]
    assert initial_tranche_token_assets[1] < final_tranche_token_assets[1]


def test_senior_tranche_should_only_be_affected_after_junior_is_empty(
    admin, users, tranche_fixed_rate, tokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets / 3)
    first_loss_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # loss should have been absorbed by junior tranche_fixed_rate
    assert first_loss_tranche_token_assets[0] < 1e14  # small amount left
    assert initial_tranche_token_assets[1] > first_loss_tranche_token_assets[1]
    token_assets = tokens[0].totalAssets()
    tokens[0].setTotalAssets(token_assets - 1e18)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # loss should now exist on both tranche_fixed_rates
    assert final_tranche_token_assets[0] == 0
    assert initial_tranche_token_assets[1] > final_tranche_token_assets[1]


def test_senior_tranche_should_get_fixed_rate_return(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # one year should give 2% of senior from junior to senior
    move_time(YEAR_IN_SECONDS)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert final_tranche_token_assets[1] / initial_tranche_token_assets[1] == 1.02
    assert (
        initial_tranche_token_assets[0]
        - (final_tranche_token_assets[1] - initial_tranche_token_assets[1])
        == final_tranche_token_assets[0]
    )


def test_senior_tranche_should_get_fixed_rate_return_changes_in_senior_depth(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens, gTokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # 1/2 year should give 1% of senior from junior to senior
    move_time(YEAR_IN_SECONDS / 2)
    pre_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    tranche_fixed_rate.withdraw(
        gTokens[SENIOR_TRANCHE].balanceOf(user.address) / 3,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    post_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    move_time(YEAR_IN_SECONDS / 2)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        (
            (final_tranche_token_assets[1] / post_withdrawal_tranche_token_assets[1])
            + (pre_withdrawal_tranche_token_assets[1] / initial_tranche_token_assets[1])
        ),
        1.01 * 2,
    )
    assert math.isclose(
        initial_tranche_token_assets[0]
        - (
            (final_tranche_token_assets[1] - post_withdrawal_tranche_token_assets[1])
            + (pre_withdrawal_tranche_token_assets[1] - initial_tranche_token_assets[1])
        ),
        final_tranche_token_assets[0],
    )


def test_senior_tranche_should_get_fixed_rate_return_changes_in_junior_depth(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens, gTokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    tranche_fixed_rate.setUtilisationThreshold(10000, {"from": admin})
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # 1/2 year should give 1% of senior from junior to senior
    move_time(YEAR_IN_SECONDS / 2)
    pull_out_assets = gTokens[JUNIOR_TRANCHE].balanceOf(user.address) / 5
    pull_out_assets_value = gTokens[JUNIOR_TRANCHE].getShareAssets(pull_out_assets)
    pre_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    tranche_fixed_rate.withdraw(
        pull_out_assets,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    post_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    move_time(YEAR_IN_SECONDS / 2)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        (
            (final_tranche_token_assets[1] / post_withdrawal_tranche_token_assets[1])
            + (pre_withdrawal_tranche_token_assets[1] / initial_tranche_token_assets[1])
        ),
        1.01 * 2,
    )
    assert math.isclose(
        initial_tranche_token_assets[0]
        - (final_tranche_token_assets[1] - initial_tranche_token_assets[1])
        - pull_out_assets_value,
        final_tranche_token_assets[0],
    )


def test_junior_tranche_gets_full_yield(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens, gTokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    # one year should give 2% of junior to senior
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    token_assets = tokens[0].totalAssets()
    tranche_token_share = (
        tokens[0].balanceOf(tranche_fixed_rate.address) / tokens[0].totalSupply()
    )
    tokens[0].setTotalAssets(token_assets * 2)
    move_time(100)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        (final_tranche_token_assets[0] - initial_tranche_token_assets[0])
        / (token_assets * tranche_token_share),
        1,
        abs_tol=0.000001,
    )
    assert final_tranche_token_assets[1] > initial_tranche_token_assets[1]


def test_senior_tranche_should_get_fixed_rate_return_new_rate_1_year(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens, gTokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    tranche_fixed_rate.setUtilisationThreshold(10000, {"from": admin})
    get_pnl_fixed_rate.setRate(300, {"from": admin})
    # one year should give 2% of senior from junior to senior before interaction
    move_time(YEAR_IN_SECONDS)
    post_change_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        post_change_tranche_token_assets[1] / initial_tranche_token_assets[1],
        1.02,
        abs_tol=0.000001,
    )
    assert math.isclose(
        initial_tranche_token_assets[0]
        - (post_change_tranche_token_assets[1] - initial_tranche_token_assets[1]),
        post_change_tranche_token_assets[0],
    )

    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    pre_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    tranche_fixed_rate.withdraw(
        1,
        token_index,
        JUNIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    # post interaction should now give 3% yield
    move_time(YEAR_IN_SECONDS)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        final_tranche_token_assets[1] / pre_withdrawal_tranche_token_assets[1],
        1.03,
        abs_tol=0.000001,
    )
    assert math.isclose(
        (
            pre_withdrawal_tranche_token_assets[0]
            - (final_tranche_token_assets[1] - pre_withdrawal_tranche_token_assets[1])
        )
        / final_tranche_token_assets[0],
        1,
    )


def test_senior_tranche_should_get_fixed_rate_return_new_rate_6_months(
    admin, users, tranche_fixed_rate, get_pnl_fixed_rate, tokens, gTokens
):
    setup_tranche(tokens, LARGE_NUMBER, users, tranche_fixed_rate)
    token_index = 0
    user = users[0]
    _amount = LARGE_NUMBER * 10 ** tokens[token_index].decimals()
    setup_token(tokens[token_index], _amount, user, tranche_fixed_rate)
    initial_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # 1/2 year should give 1% of senior from junior to senior
    move_time(YEAR_IN_SECONDS / 2)
    pre_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    get_pnl_fixed_rate.setRate(400, {"from": admin})
    tranche_fixed_rate.withdraw(
        1,
        token_index,
        SENIOR_TRANCHE,
        user.address,
        {"from": user.address},
    )
    post_withdrawal_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    # 1/2 year should give 2% of senior from junior to senior
    move_time(YEAR_IN_SECONDS / 2)
    final_tranche_token_assets = tranche_fixed_rate.pnlDistribution()[0]
    assert math.isclose(
        (
            (final_tranche_token_assets[1] / post_withdrawal_tranche_token_assets[1])
            + (pre_withdrawal_tranche_token_assets[1] / initial_tranche_token_assets[1])
        ),
        1.01 + 1.02,
    )
    assert math.isclose(
        initial_tranche_token_assets[0]
        - (
            (final_tranche_token_assets[1] - post_withdrawal_tranche_token_assets[1])
            + (pre_withdrawal_tranche_token_assets[1] - initial_tranche_token_assets[1])
        ),
        final_tranche_token_assets[0],
    )

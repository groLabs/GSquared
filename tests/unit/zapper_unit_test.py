import pytest
from brownie import (
    ZERO_ADDRESS,
    GRouter,
    GVault,
    MockCurveOracle,
    MockGToken,
    MockGTranche,
    MockZapperOracle,
    StableSwap3Pool,
)
from conftest import *


@pytest.fixture(scope="function", autouse=True)
def mock_three_pool(admin, mock_dai, mock_usdc, mock_usdt, mock_three_crv):
    three_pool = admin.deploy(
        StableSwap3Pool,
        admin,
        [mock_dai.address, mock_usdc.address, mock_usdt.address],
        mock_three_crv.address,
        100,
        4000000,
        0,
    )
    mock_three_crv.set_minter(three_pool.address, {"from": admin})
    yield three_pool


@pytest.fixture(scope="function", autouse=True)
def mock_curve_oracle(admin):
    mock_curve_oracle = admin.deploy(MockCurveOracle)
    yield mock_curve_oracle


@pytest.fixture(scope="function", autouse=True)
def junior_tranche_token(admin):
    junior_tranche_token = admin.deploy(MockGToken, "JUNIOR", "GVT")
    yield junior_tranche_token


@pytest.fixture(scope="function", autouse=True)
def senior_tranche_token(admin):
    senior_tranche_token = admin.deploy(MockGToken, "SENIOR", "PWRD")
    yield senior_tranche_token


@pytest.fixture(scope="function", autouse=True)
def mock_gtranche(
    admin,
    mock_gro_vault_curve,
    junior_tranche_token,
    senior_tranche_token,
    mock_curve_oracle,
):
    mock_gtranche = admin.deploy(
        MockGTranche,
        [mock_gro_vault_curve.address],
        [junior_tranche_token, senior_tranche_token],
        mock_curve_oracle.address,
    )
    yield mock_gtranche


@pytest.fixture(scope="function", autouse=True)
def mock_zapper_oracle(admin, mock_dai, mock_usdc, mock_usdt):
    mock_zapper_oracle = admin.deploy(
        MockZapperOracle,
        [mock_dai.address, mock_usdc.address, mock_usdt.address],
    )
    yield mock_zapper_oracle


@pytest.fixture(scope="function", autouse=True)
def gro_zapper(
    admin,
    mock_gtranche,
    mock_gro_vault_curve,
    mock_zapper_oracle,
    mock_three_pool,
    mock_three_crv,
):
    gro_zapper = admin.deploy(
        GRouter,
        mock_gtranche.address,
        mock_gro_vault_curve.address,
        mock_zapper_oracle.address,
        mock_three_pool.address,
        mock_three_crv.address,
    )
    yield gro_zapper


@pytest.fixture(scope="function", autouse=True)
def load_up_three_pool(mock_dai, mock_usdc, mock_usdt, mock_three_pool, accounts):
    mock_dai.faucet({"from": accounts[9]})
    mock_usdc.faucet({"from": accounts[9]})
    mock_usdt.faucet({"from": accounts[9]})
    mock_dai.approve(mock_three_pool.address, MAX_UINT256, {"from": accounts[9]})
    mock_usdc.approve(mock_three_pool.address, MAX_UINT256, {"from": accounts[9]})
    mock_usdt.approve(mock_three_pool.address, MAX_UINT256, {"from": accounts[9]})
    mock_three_pool.add_liquidity([1e22, 1e10, 1e10], 0, {"from": accounts[9]})


# Test that user can deposit  and withdraw via the Zapper
def test_user_can_deposit_and_withdraw(
    gro_zapper, mock_dai, mock_usdc, alice, junior_tranche_token, senior_tranche_token
):
    mock_dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(1000 * 10**18, 0, False, 9900, {"from": alice})
    junior_balance = junior_tranche_token.balanceOf(alice)
    assert junior_balance > 0
    mock_usdc.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(100 * 10**6, 1, True, 9900, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0
    senior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(senior_balance, 0, True, 0, {"from": alice})
    assert mock_dai.balanceOf(alice) > 99000 * 10**18
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(junior_balance, 1, False, 0, {"from": alice})
    assert mock_usdc.balanceOf(alice) > 99900 * 10**6


# Test that user can deposit  and withdraw via the Zapper for legacy functions
def test_user_can_deposit_and_withdraw_legacy(
    gro_zapper, mock_dai, mock_usdc, alice, junior_tranche_token, senior_tranche_token
):
    mock_dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.depositGvt([1000 * 10**18, 0, 0], 0, ZERO_ADDRESS, {"from": alice})
    junior_balance = junior_tranche_token.balanceOf(alice)
    assert junior_balance > 0
    mock_usdc.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.depositPwrd([0, 100 * 10**6, 0], 0, ZERO_ADDRESS, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0
    senior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdrawByStablecoin(True, 0, senior_balance, 0, {"from": alice})
    assert mock_dai.balanceOf(alice) > 99000 * 10**18
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdrawByStablecoin(False, 1, junior_balance, 0, {"from": alice})
    assert mock_usdc.balanceOf(alice) > 99900 * 10**6

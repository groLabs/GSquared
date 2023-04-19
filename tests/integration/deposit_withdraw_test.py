import brownie
import eth_abi
import pytest
from brownie import (
    ZERO_ADDRESS,
    Contract,
    ConvexStrategy,
    GRouter,
    GTranche,
    GVault,
    JuniorTranche,
    RouterOracle,
    SeniorTranche,
    accounts,
    chain,
    web3,
)
from conftest import *

# RUN TESTS IN THIS FILE ON MAINNET FORK


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture(scope="function")
def primary_strategy(admin, gro_vault):
    primary_strategy = admin.deploy(
        ConvexStrategy,
        gro_vault,
        admin,
        32,
        "0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B",
    )
    primary_strategy.setKeeper(admin, {"from": admin})
    gro_vault.addStrategy(primary_strategy.address, 10000, {"from": admin})
    return primary_strategy


@pytest.fixture(scope="function", autouse=True)
def junior_tranche_token(gTokens):
    junior_tranche_token = gTokens[0]
    yield junior_tranche_token


@pytest.fixture(scope="function", autouse=True)
def senior_tranche_token(gTokens):
    senior_tranche_token = gTokens[1]
    yield senior_tranche_token


@pytest.fixture(scope="function", autouse=True)
def gtranche(admin, gro_vault, junior_tranche_token, senior_tranche_token, oracle):
    gtranche = admin.deploy(
        GTranche,
        [gro_vault.address],
        [junior_tranche_token, senior_tranche_token],
        oracle.address,
    )
    junior_tranche_token.setGTranche(gtranche.address, {"from": admin})
    junior_tranche_token.addToWhitelist(gtranche.address, {"from": admin})
    senior_tranche_token.setGTranche(gtranche.address, {"from": admin})
    senior_tranche_token.addToWhitelist(gtranche.address, {"from": admin})
    pnl = deploy_pnl(admin, gtranche)
    gtranche.setPnL(pnl)
    yield gtranche


@pytest.fixture(scope="function", autouse=True)
def zapper_oracle():
    zapper_oracle = accounts[0].deploy(
        RouterOracle,
        [
            "0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9",
            "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6",
            "0x3e7d1eab13ad0104d2750b8863b489d65364e32d",
        ],
    )
    yield zapper_oracle


@pytest.fixture(scope="function", autouse=True)
def gro_zapper(admin, gtranche, gro_vault, zapper_oracle):
    gro_zapper = admin.deploy(
        GRouter,
        gtranche.address,
        gro_vault.address,
        zapper_oracle.address,
        "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7",
        "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490",
    )
    yield gro_zapper


@pytest.fixture(scope="function")
def curve_pool_frax():
    yield Contract("0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B")


def deploy_pnl(admin, tranche):
    return accounts[0].deploy(PnL, tranche)


# GIVEN a fresh deployment of GSquared with MockGTokens
# WHEN a user deposits into both JNR/SNR Tranches
# THEN they can withdraw from both successfully
def test_user_can_deposit_and_withdraw(
    gro_zapper,
    dai,
    usdt,
    alice,
    junior_tranche_token,
    senior_tranche_token,
):
    mint_dai(alice, 100_000 * 10**18)
    mint_usdt(alice, 100_000 * 10**6)

    # deposit for GVT
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    junior_balance = junior_tranche_token.balanceOf(alice)
    assert junior_balance > 0

    # deposit PWRD
    usdt.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(1_000 * 10**6, 2, True, 0, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0

    # withdraw PWRD
    senior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(senior_balance, 0, True, 0, {"from": alice})
    assert dai.balanceOf(alice) > 90_900 * 10**18

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(
        junior_balance * 0.999, 2, False, 0, {"from": alice}
    )  # Need to account for being first deposit
    assert usdt.balanceOf(alice) > 99_000 * 10**6

# GIVEN a fresh deployment of GSquared with MockGTokens
# WHEN a user deposits into both JNR/SNR Tranches
# THEN they can withdraw from both successfully
def test_user_can_deposit_and_withdraw_3crv(
    gro_zapper,
    dai,
    usdt,
    E_CRV,
    alice,
    junior_tranche_token,
    senior_tranche_token,
):
    mint_3crv(alice, 11_000 * 10**18)

    # deposit for GVT
    E_CRV.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 3, False, 0, {"from": alice})
    junior_balance = junior_tranche_token.balanceOf(alice)
    assert junior_balance > 0

    # deposit PWRD
    gro_zapper.deposit(1_000 * 10**18, 3, True, 0, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0

    # withdraw PWRD
    senior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(senior_balance, 3, True, 0, {"from": alice})
    assert E_CRV.balanceOf(alice) == 1000 * 10**18

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(
        junior_balance * 0.999, 3, False, 0, {"from": alice}
    )  # Need to account for being first deposit
    assert E_CRV.balanceOf(alice) > 99_000 * 10**6

# GIVEN a fresh deployment of GSquared with MockGTokens
# and utlisation ratio set to 50%
# WHEN utilisation is at 45%
# THEN a user can't deposit PWRD and take utilisation over 50%
# also a user can't withdraw Vault and take utilisation over 50%
def test_utilisation_ratio(
    gro_zapper, dai, alice, junior_tranche_token, senior_tranche_token
):
    mint_dai(alice, 100_000 * 10**18)
    mint_usdt(alice, 100_000 * 10**6)
    # deposit GVT
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    junior_balance = junior_tranche_token.balanceOf(alice)
    assert junior_balance > 0

    # deposit PWRD
    gro_zapper.deposit(10_000 * 10**18, 0, True, 0, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0

    # Can't deposit PWRD to take utilsiation over 50%
    with brownie.reverts(error_string("UtilisationTooHigh()")):
        gro_zapper.deposit(1_000 * 10**18, 0, True, 0, {"from": alice})

    # Can't withdraw Vault to take utilsiation over 50%
    with brownie.reverts(error_string("UtilisationTooHigh()")):
        junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
        gro_zapper.withdraw(junior_balance * 0.2, 1, False, 0, {"from": alice})


# GIVEN a fresh deployment of GSquared with MockGTokens
# and the vault strategy makes a profit with a performance fee of 10%
# pass enough time on the chain to account for slow release
# WHEN a user deposits into JNR Tranche before a strategy profit and
# withdraws JNR afterwards
# THEN a user is about to realise those profits by withdrawing the SNR Tranche
# and the rewards address is minted the fee correctly
def test_deposit_and_profit_and_prof_fee(
    gro_zapper,
    dai,
    alice,
    junior_tranche_token,
    gro_vault,
    admin,
    primary_strategy,
    gtranche,
):
    mint_dai(alice, 100_000 * 10**18)
    # set performance fee of 10% on the GVault
    gro_vault.setVaultFee(1000, {"from": admin})
    # set rewards address
    gro_vault.setFeeCollector(admin, {"from": admin})

    new_release_time = 6 * 60 * 60
    gro_vault.setProfitRelease(new_release_time)
    # alice deposits funds into junior tranche
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    alice_junior_balance = junior_tranche_token.balanceOf(alice)
    assert alice_junior_balance > 0

    # harvest to send funds to strategy
    primary_strategy.runHarvest({"from": admin})

    # send 3crv to strategy to mock profit

    mint_3crv(primary_strategy, 3_000 * 10**18)

    # harvest to realise profits
    primary_strategy.runHarvest({"from": admin})

    # check performance fee sent to admin
    assert gro_vault.balanceOf(admin) > 0

    # pass 6 hours for slow release
    chain.mine(timedelta=21600)

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    dai_withdrawn = gro_zapper.withdraw(
        alice_junior_balance / 2, 0, False, 0, {"from": alice}
    )

    assert dai_withdrawn.return_value > 5_000 * 10**18


# GIVEN a fresh deployment of GSquared with MockGTokens
# and the vault strategy makes a profit with a performance fee of 0%
# pass enough time on the chain to account for slow release
# WHEN a user deposits into JNR Tranches before a strategy profit and
# withdraws JNR afterwards
# THEN a user is about to realise those profits by withdrawing the SNR Tranche
# and the rewards address is minted NO FEE
def test_deposit_and_profit_no_perf_fee(
    gro_zapper,
    dai,
    alice,
    junior_tranche_token,
    gro_vault,
    admin,
    primary_strategy,
    gtranche,
):
    mint_dai(alice, 100_000 * 10**18)
    # set rewards address
    gro_vault.setFeeCollector(admin, {"from": admin})

    # alice deposits funds into junior tranche
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    alice_junior_balance = junior_tranche_token.balanceOf(alice)
    assert alice_junior_balance > 0

    # harvest to send funds to strategy
    primary_strategy.runHarvest({"from": admin})

    # send 3crv to strategy to mock profit
    mint_3crv(primary_strategy, 3_000 * 10**18)

    # harvest to realise profits
    primary_strategy.runHarvest({"from": admin})

    # check performance fee sent to admin
    assert gro_vault.balanceOf(admin) == 0

    # pass 6 hours for slow release
    chain.mine(timedelta=21600)

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    dai_withdrawn = gro_zapper.withdraw(
        alice_junior_balance / 2, 0, False, 0, {"from": alice}
    )

    assert dai_withdrawn.return_value > 5_000 * 10**18


# GIVEN a fresh deployment of GSquared with MockGTokens
# and the vault strategy has paper profits that are not realised
# pass enough time on the chain to account for slow release
# WHEN a user deposits into the JNR Tranche before a strategy profit has paper and
# withdraws JNR afterwards without a harvest to realise those profits
# THEN a user won't realise those profits by withdrawing the SNR Tranche
# and the rewards address is minted NO FEE


def test_deposit_and_paper_profits_no_perf_fee(
    gro_zapper,
    dai,
    alice,
    junior_tranche_token,
    gro_vault,
    admin,
    primary_strategy,
    gtranche,
):
    mint_dai(alice, 100_000 * 10**18)
    # set rewards address
    gro_vault.setFeeCollector(admin, {"from": admin})

    # alice deposits funds into junior tranche
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    alice_junior_balance = junior_tranche_token.balanceOf(alice)
    assert alice_junior_balance > 0

    # harvest to send funds to strategy
    primary_strategy.runHarvest({"from": admin})

    # send 3crv to strategy to mock profit
    mint_3crv(primary_strategy, 3_000 * 10**18)

    # check performance fee sent to admin
    assert gro_vault.balanceOf(admin) == 0

    # pass 6 hours for slow release
    chain.mine(timedelta=21600)

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    dai_withdrawn = gro_zapper.withdraw(
        alice_junior_balance / 2, 0, False, 0, {"from": alice}
    )

    assert dai_withdrawn.return_value <= 5_000 * 10**18


# GIVEN a fresh deployment of GSquared with MockGTokens
# and the vault strategy makes a Loss
# Ensure the loss is realised
# WHEN a user deposits into JNR Tranche before a strategy profit and
# withdraws JNR afterwards
# THEN a user is about to realise those Loss by withdrawing the SNR Tranche
# and the rewards address is minted the NO FEE


def test_deposit_and_loss_realised(
    gro_zapper,
    dai,
    alice,
    junior_tranche_token,
    gro_vault,
    admin,
    primary_strategy,
    gtranche,
    curve_pool_frax,
):
    mint_dai(alice, 100_000 * 10**18)

    # alice deposits funds into junior tranche
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    alice_junior_balance = junior_tranche_token.balanceOf(alice)
    assert alice_junior_balance > 0

    # harvest to send funds to strategy
    primary_strategy.runHarvest({"from": admin})

    # simulate loss by taking funds
    loss_amount = 10**24
    mint_frax_crv(admin, loss_amount)
    curve_pool_frax.remove_liquidity_one_coin(
        curve_pool_frax.balanceOf(admin), 1, 0, {"from": admin}
    )

    # harvest to realise loss
    primary_strategy.runHarvest({"from": admin})

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    dai_withdrawn = gro_zapper.withdraw(
        alice_junior_balance / 2, 0, False, 0, {"from": alice}
    )

    assert dai_withdrawn.return_value < 5_000 * 10**18


# GIVEN a fresh deployment of GSquared with MockGTokens
# and the vault strategy makes a Loss with a performance fee of 0%
# Ensure the loss is Unrealised
# WHEN a user deposits into both JNR/SNR Tranches before a strategy profit and
# withdraws SNR afterwards
# THEN a user is about to realise the entire Loss by withdrawing the SNR Tranche
# and the rewards address is minted the NO FEE


def test_deposit_and_loss_not_realised(
    gro_zapper,
    dai,
    alice,
    junior_tranche_token,
    gro_vault,
    admin,
    primary_strategy,
    gtranche,
    curve_pool_frax,
):
    mint_dai(alice, 100_000 * 10**18)

    # alice deposits funds into junior tranche
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": alice})
    alice_junior_balance = junior_tranche_token.balanceOf(alice)
    assert alice_junior_balance > 0

    # harvest to send funds to strategy
    primary_strategy.runHarvest({"from": admin})

    # simulate loss by taking funds
    loss_amount = 10**24
    mint_frax_crv(admin, loss_amount)
    curve_pool_frax.remove_liquidity_one_coin(
        curve_pool_frax.balanceOf(admin), 1, 0, {"from": admin}
    )

    # withdraw without realising loss to check if loss is realised by user
    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    dai_withdrawn = gro_zapper.withdraw(
        alice_junior_balance / 2, 0, False, 0, {"from": alice}
    )
    assert dai_withdrawn.return_value < 5_000 * 10**18


# GIVEN a fresh deployment of GSquared with MockGTokens
# WHEN multiple users deposits into JNR/SNR Tranches
# THEN they can withdraw successfully
def test_user_can_deposit_and_withdraw_multiple_users(
    gro_zapper,
    dai,
    usdt,
    alice,
    bob,
    admin,
    junior_tranche_token,
    senior_tranche_token,
    gro_vault,
    gtranche,
):
    mint_dai(alice, 100_000 * 10**18)
    mint_usdt(alice, 100_000 * 10**18)
    mint_dai(bob, 100_000 * 10**18)
    mint_dai(admin, 100_000 * 10**18)

    # deposit for GVT alice
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(1_000 * 10**18, 0, False, 0, {"from": alice})
    junior_balance_alice = junior_tranche_token.balanceOf(alice)
    assert junior_balance_alice > 0

    # withdraw GVT
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(
        junior_balance_alice / 2, 0, False, 0, {"from": alice}
    )  # Need to account being initial GVT deposit
    assert dai.balanceOf(alice) > 99_487 * 10**18

    # deposit for GVT bob
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": bob})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": bob})
    junior_balance_bob = junior_tranche_token.balanceOf(bob)
    assert junior_balance_bob > 0

    # deposit for GVT admin
    dai.approve(gro_zapper.address, MAX_UINT256, {"from": admin})
    gro_zapper.deposit(10_000 * 10**18, 0, False, 0, {"from": admin})
    junior_balance_admin = junior_tranche_token.balanceOf(admin)
    assert junior_balance_admin > 0

    # deposit PWRD
    usdt.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.deposit(1_000 * 10**6, 2, True, 0, {"from": alice})
    senior_balance = senior_tranche_token.balanceOf(alice)
    assert senior_balance > 0

    # withdraw PWRD
    senior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": alice})
    gro_zapper.withdraw(senior_balance, 0, True, 0, {"from": alice})
    assert dai.balanceOf(alice) > 91_900 * 10**18

    # withdraw GVT bob
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": bob})
    gro_zapper.withdraw(junior_balance_bob, 2, False, 0, {"from": bob})
    assert usdt.balanceOf(bob) > 9_900 * 10**6

    # withdraw GVT admin
    junior_tranche_token.approve(gro_zapper.address, MAX_UINT256, {"from": admin})
    gro_zapper.withdraw(junior_balance_admin, 0, False, 0, {"from": admin})
    assert dai.balanceOf(admin) > 99_000 * 10**18

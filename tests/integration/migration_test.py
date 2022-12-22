import math

from brownie import Contract, GMigration, GTranche, GVault
from conftest import *

# RUN TESTS IN THIS FILE ON MAINNET FORK

# Constants
THREE_POOL = "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7"
THREE_POOL_TOKEN = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490"
DAI_VAULT_ADAPTOR = "0x277947D84A2Ec370a636683799351acef97fec60"
USDC_VAULT_ADAPTOR = "0x9B2688DA7d80641F6E46A76889EA7F8B59771724"
USDT_VAULT_ADAPTOR = "0x6419Cb544878E8C4faA5EaF22D59d4A96E5F12FA"
PWRD = "0xF0a93d4994B3d98Fb5e3A2F90dBc2d69073Cb86b"
GVT = "0x3ADb04E127b9C0a5D36094125669d4603AC52a0c"
DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
TIMELOCK = "0x1aebe9147766936906ab56ec0693306da3539824"
BASED = "0xBa5ED108abA290BBdFDD88A0F022E2357349566a"
COFFEE = "0xc0ffEeDfb871B8019c5d288B4dc8E6ac42d5F655"


@pytest.fixture(scope="function", autouse=True)
def dai_vault():
    yield Contract(DAI_VAULT_ADAPTOR)


@pytest.fixture(scope="function", autouse=True)
def usdc_vault():
    yield Contract(USDC_VAULT_ADAPTOR)


@pytest.fixture(scope="function", autouse=True)
def usdt_vault():
    yield Contract(USDT_VAULT_ADAPTOR)


@pytest.fixture(scope="function", autouse=True)
def pwrd():
    yield Contract(PWRD)


@pytest.fixture(scope="function", autouse=True)
def gvt():
    yield Contract(GVT)


@pytest.fixture(scope="function", autouse=True)
def dai_token():
    yield Contract(DAI)


@pytest.fixture(scope="function", autouse=True)
def usdc_token():
    yield Contract(USDC)


@pytest.fixture(scope="function", autouse=True)
def usdt_token():
    yield Contract(USDT)


@pytest.fixture(scope="function", autouse=True)
def gmigration(admin, gvault):
    gmigration = admin.deploy(GMigration, gvault)
    yield gmigration


@pytest.fixture(scope="function", autouse=True)
def gvault(admin):
    gro_vault = admin.deploy(GVault, THREE_POOL_TOKEN)
    yield gro_vault


@pytest.fixture(scope="function", autouse=True)
def gtranche(admin, gvault, gvt, pwrd, oracle, gmigration):
    gtranche = admin.deploy(
        GTranche,
        [gvault.address],
        [gvt, pwrd],
        oracle.address,
        gmigration.address,
    )
    pnl = deploy_pnl(admin, gtranche)
    gtranche.setPnL(pnl)
    gmigration.setGTranche(gtranche.address, {"from": admin})
    yield gtranche


def force_slippage(strategy):
    strat = Contract(strategy)
    strat.setSlippage(250, {"from": BASED})


# GIVEN the current gro protocol and a fresh deployment of GSquared
# WHEN all the funds are correctly migrated to the new gTranche
# THEN the respective junior and senior tranche balances match
# the previous gro protocol balances
def test_migration(
    admin,
    dai_vault,
    usdc_vault,
    usdt_vault,
    pwrd,
    gvt,
    dai_token,
    usdc_token,
    usdt_token,
    gmigration,
    gtranche,
):

    # Set Debt Ratios to 0
    dai_vault.updateStrategyRatio([0, 0], {"from": TIMELOCK})
    usdc_vault.updateStrategyRatio([0, 0], {"from": TIMELOCK})
    usdt_vault.updateStrategyRatio([0], {"from": TIMELOCK})

    # make sure we can withdraw
    for vault in [dai_vault, usdc_vault, usdt_vault]:
        for i in range(5):
            strategy = Contract(vault.vault()).withdrawalQueue(i)
            if strategy == ZERO_ADDRESS:
                break
            force_slippage(strategy)

    # Harvest all strategies to get funds into Vyper Vaults
    dai_vault.strategyHarvest(0, {"from": COFFEE})
    dai_vault.strategyHarvest(1, {"from": COFFEE})
    usdc_vault.strategyHarvest(0, {"from": COFFEE})
    usdc_vault.strategyHarvest(1, {"from": COFFEE})
    usdt_vault.strategyHarvest(0, {"from": COFFEE})

    # Withdraw from vyper vaults into vault adaptors
    dai_vault.withdrawToAdapter(
        dai_token.balanceOf(dai_vault.vault()), 0, {"from": COFFEE}
    )
    usdc_vault.withdrawToAdapter(
        usdc_token.balanceOf(usdc_vault.vault()), 0, {"from": COFFEE}
    )
    usdt_vault.withdrawToAdapter(
        usdt_token.balanceOf(usdt_vault.vault()), 0, {"from": COFFEE}
    )

    expected_dai = dai_token.balanceOf(dai_vault) * 0.99  # buffer for slippage
    expected_usdc = usdc_token.balanceOf(usdc_vault) * 0.99
    expected_usdt = usdt_token.balanceOf(usdt_vault) * 0.99

    # store asset values before starting migration
    senior_tranche_value_before_migration = pwrd.totalAssets()
    junior_tranche_value_before_migration = gvt.totalAssets()

    # Migrate funds to gMigration contract
    dai_vault.migrate(gmigration, {"from": TIMELOCK})
    usdc_vault.migrate(gmigration, {"from": TIMELOCK})
    usdt_vault.migrate(gmigration, {"from": TIMELOCK})

    assert dai_token.balanceOf(gmigration) > expected_dai
    assert usdc_token.balanceOf(gmigration) > expected_usdc
    assert usdt_token.balanceOf(gmigration) > expected_usdt

    three_pool = Contract(THREE_POOL)
    three_crv_amount = three_pool.calc_token_amount(
        [
            dai_token.balanceOf(gmigration),
            usdc_token.balanceOf(gmigration),
            usdt_token.balanceOf(gmigration),
        ],
        True,
    )

    # run migration
    gmigration.prepareMigration(three_crv_amount * 0.99, 0, {"from": admin})
    gtranche.migrateFromOldTranche({"from": admin})

    junior_balance_post_migration = gtranche.trancheBalances(False)
    senior_balance_post_migration = gtranche.trancheBalances(True)

    assert junior_balance_post_migration >= junior_tranche_value_before_migration * 0.99
    assert math.isclose(
        senior_balance_post_migration, senior_tranche_value_before_migration, abs_tol=1
    )

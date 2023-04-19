import json
import os
from distutils.util import strtobool

from brownie import (
    CurveOracle,
    GRouter,
    GTranche,
    GVault,
    JuniorTranche,
    MockDAI,
    MockUSDC,
    MockUSDT,
    PnLFixedRate,
    RouterOracle,
    SeniorTranche,
    StopLossLogic,
    accounts,
    chain,
    web3,
)
from dotenv import load_dotenv

from .addresses import *
from .curve_convex_pools import *

MAX_UINT256 = 2**256 - 1
MIN_DELAY = 259200
ZERO = "0x0000000000000000000000000000000000000000"

dai_vault_adapter = Contract(DAI_VAULT_ADAPTOR_ADDRESS)
usdc_vault_adapter = Contract(USDC_VAULT_ADAPTOR_ADDRESS)
usdt_vault_adapter = Contract(USDT_VAULT_ADAPTOR_ADDRESS)

dai_vault = Contract(dai_vault_adapter.vault())
usdc_vault = Contract(usdc_vault_adapter.vault())
usdt_vault = Contract(usdt_vault_adapter.vault())

GPC = Contract(GPC_ADDRESS)

load_dotenv()

local = strtobool(os.getenv("env"))
PUBLISH_SOURCE = strtobool(os.getenv("PUBLISH_SOURCE"))

gro_timelock_controller = Contract(TIMELOCK_ADDRESS)
dai = MockDAI.at(DAI_ADDRESS)
usdc = MockUSDC.at(USDC_ADDRESS)
usdt = MockUSDT.at(USDT_ADDRESS)

pwrd = SeniorTranche.at(PWRD_ADDRESS)  # admin.deploy(SeniorTranche, "senior", "snr")
gvt = JuniorTranche.at(GVT_ADDRESS)  # admin.deploy(JuniorTranche, "junior", "jnr")
salt = 123456789


def load_deployed_contracts():
    # Load contract addresses
    with open("mainnet_fork_deployments.json") as json_file:
        contract_data = json.load(json_file)
    return contract_data


def migration_data():
    contract_data = load_deployed_contracts()

    data_payload = {}
    data_payload[1] = dai_vault_adapter.migrate.encode_input(
        contract_data.get("GMigration", ZERO)
    )
    data_payload[2] = usdc_vault_adapter.migrate.encode_input(
        contract_data.get("GMigration", ZERO)
    )
    data_payload[3] = usdt_vault_adapter.migrate.encode_input(
        contract_data.get("GMigration", ZERO)
    )
    data_payload[4] = gvt.addToWhitelist.encode_input(
        contract_data.get("GTranche", ZERO)
    )
    data_payload[5] = gvt.setGTranche.encode_input(
        contract_data.get("GTranche", ZERO)
    )
    data_payload[6] = pwrd.addToWhitelist.encode_input(
        contract_data.get("GTranche", ZERO)
    )
    data_payload[7] = pwrd.setGTranche.encode_input(
        contract_data.get("GTranche", ZERO)
    )

    return contract_data, data_payload


def load_account(local=False, account=None):
    if local:
        with open(f"./{account}") as keyfile:
            encrypted_key = keyfile.read()
            pass_ = os.getenv(account)
            private_key = web3.eth.account.decrypt(encrypted_key, pass_)
        return accounts.add(private_key)
    else:
        web3.provider.make_request("hardhat_impersonateAccount", [os.getenv(account)])
        return accounts.at(os.getenv(account), force=True)


admin = load_account(local, "deployer")
bot = load_account(local, "bot")


def migrate(minThreeCrv, minShares):
    timelock_admin = load_account(local, "timelock_admin")

    print(minThreeCrv, minShares)
    minThreeCrv = int(float(minThreeCrv) * 1e18)
    minShares = int(float(minShares) * 1e18)

    if not local:
        print("move time")
        chain.mine(timedelta=MIN_DELAY)

    contract_data, data_payload = migration_data()
    print(data_payload)

    pwrd_init_factor = pwrd.factor()
    pwrd_init_total_supply = pwrd.totalSupply()
    pwrd_init_total_base = pwrd.totalSupplyBase()
    gvt_init_factor = gvt.factor()
    gvt_init_total_supply = gvt.totalSupply()

    # send funds to gmigration
    totalAssets = [
        dai_vault_adapter.totalAssets() / 10**18,
        usdc_vault_adapter.totalAssets() / 10**6,
        usdt_vault_adapter.totalAssets() / 10**6,
    ]
    print("execute dai vault migration target")
    gro_timelock_controller.execute(
        dai_vault_adapter.address,
        0,
        data_payload[1],
        ZERO,
        salt,
        {"from": timelock_admin.address},
    )
    print("execute usdc vault migration target")
    gro_timelock_controller.execute(
        usdc_vault_adapter.address,
        0,
        data_payload[2],
        ZERO,
        salt,
        {"from": timelock_admin.address},
    )
    print("execute usdt vault migration target")
    gro_timelock_controller.execute(
        usdt_vault_adapter.address,
        0,
        data_payload[3],
        ZERO,
        salt,
        {"from": timelock_admin.address},
    )

    # run migration
    gmigration = GMigration.at(contract_data.get("GMigration", ZERO))
    gtranche = GTranche.at(contract_data.get("GTranche", ZERO))
    print("set gtranche in migration")
    gmigration.setGTranche(gtranche.address, {"from": admin.address})
    print("perapre migration")
    gmigration.prepareMigration(minThreeCrv, minShares, {"from": admin.address})
    print("execute migration")
    gtranche.migrateFromOldTranche({"from": admin.address})

    # whitelist GTranche on GTokens and set controller
    print("execute gvt whitelist update")
    gro_timelock_controller.execute(
        gvt.address, 0, data_payload[4], ZERO, salt, {"from": admin.address}
    )
    print("execute gvt ownership change")
    gro_timelock_controller.execute(
        gvt.address, 0, data_payload[5], ZERO, salt, {"from": admin.address}
    )
    print("execute pwrd whitelist update")
    gro_timelock_controller.execute(
        pwrd.address, 0, data_payload[6], ZERO, salt, {"from": admin.address}
    )
    print("execute pwrd ownersup update")
    gro_timelock_controller.execute(
        pwrd.address, 0, data_payload[7], ZERO, salt, {"from": admin.address}
    )
    print(f"GTranche totalAssets {gtranche.tokenBalances(0)}")
    print(
        f"junior {gtranche.trancheBalances(False)/10**18}, \
        senior {gtranche.trancheBalances(True)/10**18}"
    )
    print(f"init balance {totalAssets}")
    gTranche_sum = (
        gtranche.trancheBalances(False) / 10**18
        + gtranche.trancheBalances(True) / 10**18
    )
    print(
        f"init balance sum {sum(totalAssets)} \
        gtranche sum \
        {gTranche_sum}"
    )

    print(
        f"pwrd init pps {pwrd_init_factor} \
        pwrd init totalSupply {pwrd_init_total_supply} \
        pwrd init totalSupplyBase {pwrd_init_total_base}"
    )
    print(
        f"gvt init pps {gvt_init_factor} \
        gvt init totalSupply {gvt_init_total_supply}"
    )
    print(
        f"pwrd pps {pwrd.factor()} \
        pwrd totalSupply {pwrd.totalSupply()} \
        pwrd totalSupplyBase {pwrd.totalSupplyBase()}"
    )
    print(f"gvt pps {gvt.factor()} gvt totalSupply {gvt.totalSupply()}")


def harvest_all():

    dai_total_assets_init = dai_vault_adapter.totalAssets()
    usdc_total_assets_init = usdc_vault_adapter.totalAssets()
    usdt_total_assets_init = usdt_vault_adapter.totalAssets()

    print("update strategyDebt ratio for dai vault")
    dai_vault.updateStrategyDebtRatio(DAI_STRATEGY_1, 0, {"from": admin.address})
    dai_vault.updateStrategyDebtRatio(DAI_STRATEGY_2, 0, {"from": admin.address})
    usdc_vault.updateStrategyDebtRatio(USDC_STRATEGY_1, 0, {"from": admin.address})
    usdc_vault.updateStrategyDebtRatio(USDC_STRATEGY_2, 0, {"from": admin.address})
    usdt_vault.updateStrategyDebtRatio(USDT_STRATEGY_1, 0, {"from": admin.address})

    # set slippage for strategy to allow harvest
    print("set dai prim slippage")
    dai_strategy_1 = Contract(DAI_STRATEGY_1)
    dai_strategy_1.setSlippage(50, {"from": admin.address})
    print("set dai sec slippage")
    dai_strategy_2 = Contract(DAI_STRATEGY_2)
    dai_strategy_2.setSlippage(50, {"from": admin.address})
    print("set usdc prim slippage")
    usdc_strategy_1 = Contract(USDC_STRATEGY_1)
    usdc_strategy_1.setSlippage(50, {"from": admin.address})
    print("set usdc sec slippage")
    usdc_strategy_2 = Contract(USDC_STRATEGY_2)
    usdc_strategy_2.setSlippage(50, {"from": admin.address})
    print("set usdt prim slippage")
    usdt_strategy_1 = Contract(USDT_STRATEGY_1)
    usdt_strategy_1.setSlippage(50, {"from": admin.address})

    # Harvest all strategies to get funds into Vyper Vaults
    print("harvest dai prim")
    dai_vault_adapter.strategyHarvest(0, {"from": bot.address})
    print("harvest dai sec")
    dai_vault_adapter.strategyHarvest(1, {"from": bot.address})
    print("harvest usdc prim")
    usdc_vault_adapter.strategyHarvest(0, {"from": bot.address})
    print("harvest usdc sec")
    usdc_vault_adapter.strategyHarvest(1, {"from": bot.address})
    print("harvest usdt prim")
    usdt_vault_adapter.strategyHarvest(0, {"from": bot.address})

    # withdraw all funds to adaptor
    print("withdraw to dai adapter")
    print(f"dai vault totalAssets {dai.balanceOf(dai_vault_adapter.vault())}")
    dai_vault_adapter.withdrawToAdapter(
        dai.balanceOf(dai_vault_adapter.vault()), 0, {"from": bot.address}
    )
    print("withdraw to usdc adapter")
    print(f"usdc vault totalAssets {usdc.balanceOf(usdc_vault_adapter.vault())}")
    usdc_vault_adapter.withdrawToAdapter(
        usdc.balanceOf(usdc_vault_adapter.vault()), 0, {"from": bot.address}
    )
    print("withdraw to usdt adapter")
    print(f"usdt vault totalAssets {usdt.balanceOf(usdt_vault_adapter.vault())}")
    usdt_vault_adapter.withdrawToAdapter(
        usdt.balanceOf(usdt_vault_adapter.vault()), 0, {"from": bot.address}
    )
    print(
        f"dai init {dai_total_assets_init / 10**18}, \
        dai final {dai_vault_adapter.totalAssets() / 10**18}"
    )
    print(
        f"usdc init {usdc_total_assets_init / 10**6}, \
        usdc final {usdc_vault_adapter.totalAssets() / 10**6}"
    )
    print(
        f"usdt init {usdt_total_assets_init / 10**6}, \
        usdt final {usdt_vault_adapter.totalAssets() / 10**6}"
    )
    GPC.pause({"from": bot})


def schedule_migration():

    contract_data, data_payload = migration_data()
    timelock_admin = load_account(local, "timelock_admin")

    print("set migration target for dai vault")
    gro_timelock_controller.schedule(
        dai_vault_adapter.address,
        0,
        data_payload[1],
        ZERO,
        salt,
        MIN_DELAY,
        {"from": timelock_admin.address},
    )
    print("set migration target for usdc vault")
    gro_timelock_controller.schedule(
        usdc_vault_adapter.address,
        0,
        data_payload[2],
        ZERO,
        salt,
        MIN_DELAY,
        {"from": timelock_admin.address},
    )
    print("set migration target for usdt vault")
    gro_timelock_controller.schedule(
        usdt_vault_adapter.address,
        0,
        data_payload[3],
        ZERO,
        salt,
        MIN_DELAY,
        {"from": timelock_admin.address},
    )

    print("move gtranche to gvt whitelist")
    gro_timelock_controller.schedule(
        gvt.address, 0, data_payload[4], ZERO, salt, MIN_DELAY, {"from": timelock_admin.address}
    )
    print("move gtranche to gvt ownership")
    gro_timelock_controller.schedule(
        gvt.address, 0, data_payload[5], ZERO, salt, MIN_DELAY, {"from": timelock_admin.address}
    )
    print("move gtranche to pwrd whitelist")
    gro_timelock_controller.schedule(
        pwrd.address, 0, data_payload[6], ZERO, salt, MIN_DELAY, {"from": timelock_admin.address}
    )
    print("move gtranche to pwrd ownership")
    gro_timelock_controller.schedule(
        pwrd.address, 0, data_payload[7], ZERO, salt, MIN_DELAY, {"from": timelock_admin.address}
    )


def deploy():
    # setup contract

    # deploy GVault
    print("deploying GVault...")
    gro_vault = admin.deploy(
        GVault, THREE_POOL_TOKEN_ADDRESS, publish_source=PUBLISH_SOURCE
    )
    print(f"...deployed at {gro_vault.address}")

    print("deploying GMigration...")
    gmigration = admin.deploy(GMigration, gro_vault, publish_source=PUBLISH_SOURCE)
    print(f"...deployed at {gmigration.address}")

    # deploy curve Oracle
    print("deploying curve_oracle...")
    curve_oracle = admin.deploy(CurveOracle, publish_source=PUBLISH_SOURCE)
    print(f"...deployed at {curve_oracle.address}")
    # deploy gtranche
    print("deploying GTranche...")
    gtranche = admin.deploy(
        GTranche,
        [gro_vault],
        [gvt, pwrd],
        curve_oracle,
        gmigration.address,
        publish_source=PUBLISH_SOURCE,
    )
    print(f"...deployed at {gtranche.address}")

    # deploy router oracle
    print("deploying router oracle...")
    router_oracle = admin.deploy(
        RouterOracle, CHAINLINK_AGG_ADDRESSES, publish_source=PUBLISH_SOURCE
    )
    print(f"...deployed at {router_oracle.address}")

    # deploy GRouter
    print("deploying gro_router...")
    gro_router = admin.deploy(
        GRouter,
        gtranche,
        gro_vault,
        router_oracle,
        THREE_POOL_ADDRESS,
        THREE_POOL_TOKEN_ADDRESS,
        publish_source=PUBLISH_SOURCE,
    )
    print(f"...deployed at {gro_router.address}")

    # deploy pnl
    print("deploying pnl...")
    pnl = admin.deploy(PnLFixedRate, gtranche, publish_source=PUBLISH_SOURCE)
    print(f"...deployed at {pnl.address}")

    # add pnl to tranche
    print("add pnl to tranche...")
    gtranche.setPnL(pnl)

    # add pnl to tranche
    print("deploy strategies...")
    snl = test_snl(admin)
    strategy_frax = setup_frax_strategy(admin, gro_vault, snl)
    print(strategy_frax)
    strategy_mim = setup_mim_strategy(admin, gro_vault, snl)
    print(strategy_mim)
    strategy_ousd = setup_ousd_strategy(admin, gro_vault, snl)
    print(strategy_ousd)
    strategy_tusd = setup_tusd_strategy(admin, gro_vault, snl)
    print(strategy_tusd)
    strategy_gusd = setup_gusd_strategy(admin, gro_vault, snl)
    print(strategy_gusd)
    print("done")

    deployments = {
        "GRouter": gro_router.address,
        "RouterOracle": router_oracle.address,
        "GTranche": gtranche.address,
        "CurveOracle": curve_oracle.address,
        "GVault": gro_vault.address,
        "PnL": pnl.address,
        "GMigration": gmigration.address,
        "StopLossLogic": snl.address,
        "convexFrax": strategy_frax.address,
        "convexMim": strategy_mim.address,
        "convexGusd": strategy_gusd.address,
        "convexOusd": strategy_ousd.address,
        "convexTusd": strategy_tusd.address,
        "pwrd": pwrd.address,
        "gvt": gvt.address,
    }

    with open("mainnet_fork_deployments.json", "w") as write_file:
        json.dump(deployments, write_file, indent=4)


def deploy_strategy(debt_ratio, pid):
    pool_info = convex_deposit().poolInfo(pid)

    contract_data = load_deployed_contracts()
    gVault = GVault.at(contract_data["GVault"])
    snl = StopLossLogic.at(contract_data["StopLossLogic"])
    setup_strategy(admin, gVault, snl, pid, pool_info[0], debt_ratio)

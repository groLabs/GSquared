import os
from distutils.util import strtobool

from brownie import Contract, ConvexStrategy, StopLossLogic

from .addresses import *
from .tokens import *

PUBLISH_SOURCE = strtobool(os.getenv("PUBLISH_SOURCE"))


def curve_pools(address_curve):
    return Contract(address_curve)


def convex_pool():
    def _convex_pool(address_convex):
        return Contract(address_convex)

    yield _convex_pool


def curve_3pool():
    yield Contract(THREE_POOL_TOKEN)


def setup_strategy_in_vault(strategy, vault, admin, debt=10000):
    vault.addStrategy(strategy, debt, {"from": admin})
    strategy.runHarvest({"from": admin})


def prep_vault(user, vault, lp_token_3pool):
    mint_3crv(user, LARGE_AMOUNT)
    lp_token_3pool.approve(vault.address, LARGE_AMOUNT, {"from": user})
    vault.deposit(lp_token_3pool.balanceOf(user), user, {"from": user})


def generate_strategy(admin, pid, lp, vault, snl, amount=2000):
    strategy_convex = admin.deploy(
        ConvexStrategy, vault, admin, pid, lp, publish_source=PUBLISH_SOURCE
    )
    strategy_convex.setKeeper(admin, {"from": admin})
    setup_strategy_in_vault(strategy_convex, vault, admin, amount)
    strategy_convex.setStopLossLogic(snl, {"from": admin})
    snl.setStrategy(strategy_convex, 1e18, 400, {"from": admin})
    return strategy_convex


def test_snl(admin):
    test_snl = admin.deploy(StopLossLogic, publish_source=PUBLISH_SOURCE)
    return test_snl


def setup_strategies(admin, test_vault, test_snl):
    strategy_mim = generate_strategy(
        admin,
        convex_pools["MIM"]["pid"],
        convex_pools["MIM"]["LP_TOKEN"],
        test_vault,
        test_snl,
    )
    strategy_lusd = generate_strategy(
        admin,
        convex_pools["LUSD"]["pid"],
        convex_pools["LUSD"]["LP_TOKEN"],
        test_vault,
        test_snl,
    )
    strategy_frax = generate_strategy(
        admin,
        convex_pools["FRAX"]["pid"],
        convex_pools["FRAX"]["LP_TOKEN"],
        test_vault,
        test_snl,
    )

    return strategy_frax, strategy_mim, strategy_lusd


def setup_frax_strategy(admin, test_vault, test_snl):
    strategy_frax = generate_strategy(
        admin,
        convex_pools["FRAX"]["pid"],
        convex_pools["FRAX"]["LP_TOKEN"],
        test_vault,
        test_snl,
        2000,
    )
    return strategy_frax


def setup_mim_strategy(admin, test_vault, test_snl):
    strategy = generate_strategy(
        admin,
        convex_pools["LUSD"]["pid"],
        convex_pools["LUSD"]["LP_TOKEN"],
        test_vault,
        test_snl,
        2000,
    )
    return strategy


def setup_gusd_strategy(admin, test_vault, test_snl):
    strategy = generate_strategy(
        admin,
        convex_pools["GUSD"]["pid"],
        convex_pools["GUSD"]["LP_TOKEN"],
        test_vault,
        test_snl,
        2000,
    )
    return strategy


def setup_tusd_strategy(admin, test_vault, test_snl):
    strategy = generate_strategy(
        admin,
        convex_pools["TUSD"]["pid"],
        convex_pools["TUSD"]["LP_TOKEN"],
        test_vault,
        test_snl,
        2000,
    )
    return strategy


def setup_ousd_strategy(admin, test_vault, test_snl):
    strategy = generate_strategy(
        admin,
        convex_pools["OUSD"]["pid"],
        convex_pools["OUSD"]["LP_TOKEN"],
        test_vault,
        test_snl,
        2000,
    )
    return strategy

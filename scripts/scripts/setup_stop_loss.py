import json
import os
from distutils.util import strtobool

from brownie import *
from brownie import (
    ConvexStrategy,
    GStopLossResolver,
    GStrategyGuard,
    StopLossLogic,
    web3,
)

PUBLISH_SOURCE = strtobool(os.getenv("PUBLISH_SOURCE"))

# Load contract addresses
with open("mainnet_fork_deployments.json") as json_file:
    contract_data = json.load(json_file)

# initiate contract object for user deposits/ withdrawrals
convexMimAddr = contract_data["convexMim"]
convexLusdAddr = contract_data["convexLusd"]
convexFraxAddr = contract_data["convexFrax"]
stopLossLogicAddr = contract_data["StopLossLogic"]

convexMim = ConvexStrategy.at(convexMimAddr)
convexLusd = ConvexStrategy.at(convexLusdAddr)
convexFrax = ConvexStrategy.at(convexFraxAddr)
stopLossLogic = StopLossLogic.at(stopLossLogicAddr)


def main():
    admin = accounts[0]
    # deploy GStrategyGuard
    print("deploying GStrategyGuard...")
    guard = admin.deploy(GStrategyGuard, publish_source=PUBLISH_SOURCE)
    print(f"deployed GStrategyGuard at {guard.address}")
    # deploy GStrategyResolver
    print("deploying GStrategyResolver...")
    resolver = admin.deploy(
        GStopLossResolver, guard.address, publish_source=PUBLISH_SOURCE
    )
    print(f"deployed GStrategyResolver at {resolver.address}")

    # set admin to GStrategyGuard's keeper
    print("set admin to GStrategyGuard's keeper...")
    guard.setKeeper(admin, {"from": admin})

    # set guard to strategies's keeper
    print("set guardto convexMin's keeper...")
    convexMim.setKeeper(guard.address, {"from": admin})
    print("set guardto convexLusd's keeper...")
    convexLusd.setKeeper(guard.address, {"from": admin})
    print("set guardto convexFrax's keeper...")
    convexFrax.setKeeper(guard.address, {"from": admin})

    # init stopLossLogic contract
    equilibriumValue = 1e18
    healthThreshold = 200
    print("init convexMin's stop loss...")
    stopLossLogic.setStrategy(
        convexMimAddr, equilibriumValue, healthThreshold, {"from": admin}
    )
    print("init convexLusd's stop loss...")
    stopLossLogic.setStrategy(
        convexLusdAddr, equilibriumValue, healthThreshold, {"from": admin}
    )
    print("init convexFrax's stop loss...")
    stopLossLogic.setStrategy(
        convexFraxAddr, equilibriumValue, healthThreshold, {"from": admin}
    )

    # init strategies in guard contract
    HOUR_IN_SECONDS = 3600
    print("init convexMin's in guard...")
    guard.addStrategy(convexMimAddr, HOUR_IN_SECONDS, {"from": admin})
    print("init convexLusd's in guard...")
    guard.addStrategy(convexLusdAddr, HOUR_IN_SECONDS, {"from": admin})
    print("init convexFrax's in guard...")
    guard.addStrategy(convexFraxAddr, HOUR_IN_SECONDS, {"from": admin})

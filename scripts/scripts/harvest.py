import json
from distutils.util import strtobool

from brownie import *
from brownie import ConvexStrategy, GVault, accounts, web3

# Load contract addresses
with open("mainnet_fork_deployments.json") as json_file:
    contract_data = json.load(json_file)

# initiate contract object for user deposits/ withdrawals
gVault = GVault.at(contract_data["GVault"])


def harvest(checkTrigger, strategy=None):
    checkTrigger = strtobool(checkTrigger)
    admin = accounts[0]
    print("attempting harvest...")
    if strategy:
        strategies = {k: v for k, v in contract_data.items() if strategy in k}
    else:
        strategies = {k: v for k, v in contract_data.items() if "convex" in k}
    for pool, strat_address in strategies.items():
        strat = ConvexStrategy.at(strat_address)
        strategy_data = gVault.strategies(strat.address)
        print(f"strategy {pool}:{strat.address}, can harvest: {strat.canHarvest()}")
        print(
            f"debt: {strategy_data[3]}, \
            estimated: {strat.estimatedTotalAssets()}, \
            diff: {strat.estimatedTotalAssets() - strategy_data[3]}"
        )
        print(
            f"debt: {strategy_data[3]}, \
            profit: {strategy_data[4]}, \
            loss: {strategy_data[5]}"
        )
        if strat.canHarvest({"from": admin}) or not checkTrigger:
            strat.runHarvest({"from": admin})

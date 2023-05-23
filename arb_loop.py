import json
import os
from typing import Dict

from dotenv import load_dotenv
from eth_account import Account
from eth_account.signers.local import LocalAccount
from flashbots import flashbot
from web3 import HTTPProvider
from web3 import Web3
from web3.contract import Contract

# Addresses
ADMIN = '0xBa5ED108abA290BBdFDD88A0F022E2357349566a'
OUSD_ARB = '0x0000000000000000000000000000000000000000'  # TODO: Change once deployed
THREE_POOL_TOKEN = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490'
OUSD_STRATEGY = '0x73703f0493C08bA592AB1e321BEaD695AC5b39E3'

# Constants
CHAIN_ID = 1
AMOUNT_TO_SWAP = int(200_000e18)
MAX_UINT = 2 ** 256 - 100
SLIPPAGE = 120


def get_abi(contract_name: str) -> Dict:
    project_root_dir = os.path.abspath(os.path.dirname(__file__))
    with open(f"{project_root_dir}/abi/{contract_name}.json") as f:
        return json.load(f)


# Ref: https://github.com/flashbots/web3-flashbots/blob/master/examples/simple.py
def swap() -> None:
    load_dotenv()

    signer: LocalAccount = Account.from_key(os.environ["ADMIN_KEY"])
    web3 = Web3(HTTPProvider(os.environ["WEB3_ALCHEMY_PROJECT_ID"]))
    arb_ousd: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_ARB),
        abi=get_abi("ArbOusd")
    )

    three_pool_token: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL_TOKEN),
        abi=get_abi("ERC20")
    )

    convex_strategy: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_STRATEGY),
        abi=get_abi("ConvexStrategy")
    )

    flashbot(web3, signer)
    for i in range(9):
        bundle = []
        nonce = web3.eth.get_transaction_count(signer.address)
        options = {
            "gas": 100000,
            "maxFeePerGas": Web3.toWei(200, "gwei"),
            "maxPriorityFeePerGas": Web3.toWei(50, "gwei"),
            "nonce": nonce,
            "chainId": CHAIN_ID,
            "from": signer.address,
        }

        three_pool_allowance = three_pool_token.functions.allowance(
            ADMIN,
            arb_ousd.address
        ).call()
        if three_pool_allowance < AMOUNT_TO_SWAP:
            approve_3crv_tx = three_pool_token.functions.approve(
                arb_ousd.address,
                MAX_UINT
            ).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": approve_3crv_tx})

        # Check if arb contract has enough 3pool tokens to perform the arb
        three_pool_balance = three_pool_token.functions.balanceOf(arb_ousd.address).call()
        if three_pool_balance == 0:
            arb_with_transfer_tx = arb_ousd.functions.performArbWithTransfer(
                AMOUNT_TO_SWAP).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": arb_with_transfer_tx})
        else:
            arb_tx = arb_ousd.functions.performArb(SLIPPAGE).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": arb_tx})

        # Run harvest in the end
        harvest_tx = convex_strategy.functions.runHarvest().buildTransaction(options)
        nonce += 1
        bundle.append({"signer": signer, "transaction": harvest_tx})
        while True:
            block = web3.eth.block_number
            print(f"Simulating on block {block}")
            try:
                web3.flashbots.simulate(bundle, block)
                print("Simulation successful.")
            except Exception as e:
                print("Simulation error", e)
                return


if __name__ == "__main__":
    swap()

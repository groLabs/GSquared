import json
import os
from copy import deepcopy
from typing import Dict
from uuid import uuid4

from dotenv import load_dotenv
from eth_account import Account
from eth_account.signers.local import LocalAccount
from flashbots import flashbot
from web3 import HTTPProvider
from web3 import Web3
from web3.contract import Contract
from web3.exceptions import TransactionNotFound

# Addresses
ADMIN = "0xBa5ED108abA290BBdFDD88A0F022E2357349566a"
FRAX_ARB = "0x0ECD44E4531eB827DEEd394b5eEAd3DD6c25F726"
THREE_POOL_TOKEN = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490"
FRAX_STRATEGY = "0x60a6A86ad77EF672D93Db4408D65cf27Dd627050"

# Constants
CHAIN_ID = 1
AMOUNT_TO_SWAP = int(200_000e18)
MAX_UINT = 2**256 - 100
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
    arb_contract: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(FRAX_ARB), abi=get_abi("ArbOusd")
    )

    three_pool_token: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL_TOKEN), abi=get_abi("ERC20")
    )

    convex_strategy: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(FRAX_STRATEGY), abi=get_abi("ConvexStrategy")
    )
    # Read msig transactions from file to include them into bundle
    with open("../../msig_transactions.json") as f:
        msig_transactions = json.load(f)
    flashbot(web3, signer)
    # Run the loop 9 times as we need to decrease debtRatio of strategy
    for i in range(9):
        # Reset bundle for each arb loop
        bundle = []
        options = {
            "gas": 100000,
            "maxFeePerGas": Web3.toWei(200, "gwei"),
            "maxPriorityFeePerGas": Web3.toWei(50, "gwei"),
            "nonce": web3.eth.get_transaction_count(signer.address),
            "chainId": CHAIN_ID,
            "from": signer.address,
        }
        # Increase allowance for 3crv token if needed before sending it to arb contract
        three_pool_allowance = three_pool_token.functions.allowance(
            ADMIN, arb_contract.address
        ).call()
        if three_pool_allowance < AMOUNT_TO_SWAP:
            approve_3crv_tx = three_pool_token.functions.approve(
                arb_contract.address, MAX_UINT
            ).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": approve_3crv_tx})
        options_copy = deepcopy(options)
        options_copy["data"] = msig_transactions[i]["data"]
        options_copy["nonce"] = web3.eth.get_transaction_count(signer.address)
        msig_tx_signed = signer.sign_transaction(options_copy)
        # Execute transaction now without bundle:
        bundle.append({"signed_transaction": msig_tx_signed.rawTransaction})
        options["nonce"] += 1
        # Check if arb contract has enough 3pool tokens to perform the arb
        # If not, first transfer 3pool tokens from strategy to arb contract and then perform arb
        # If yes, perform arb without transfer, as Arb contract should already have some
        # 3pool tokens from previous arb
        three_pool_balance = three_pool_token.functions.balanceOf(
            arb_contract.address
        ).call()
        if three_pool_balance == 0:
            arb_with_transfer_tx = arb_contract.functions.performArbWithTransfer(
                AMOUNT_TO_SWAP
            ).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": arb_with_transfer_tx})
        else:
            arb_tx = arb_contract.functions.performArb(SLIPPAGE).buildTransaction(options)
            options["nonce"] += 1
            bundle.append({"signer": signer, "transaction": arb_tx})

        # Run harvest in the end
        harvest_tx = convex_strategy.functions.runHarvest().buildTransaction(options)
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
            # send bundle targeting next block
            print(f"Sending bundle targeting block {block + 1}")
            replacement_uuid = str(uuid4())
            print(f"replacementUuid {replacement_uuid}")
            send_result = web3.flashbots.send_bundle(
                bundle,
                target_block_number=block + 1,
                opts={"replacementUuid": replacement_uuid},
            )
            stats_v2 = web3.flashbots.get_bundle_stats_v2(
                web3.toHex(send_result.bundle_hash()), block
            )
            print("bundle stats:", stats_v2)
            send_result.wait()
            try:
                receipts = send_result.receipts()
                print(f"Bundle was mined in block {receipts[0].blockNumber}\a")
                break
            except TransactionNotFound:
                print(f"Bundle not found in block {block + 1}")
                # essentially a no-op but it shows that the function works
                cancel_res = web3.flashbots.cancel_bundles(replacement_uuid)
                print(f"canceled {cancel_res}")


if __name__ == "__main__":
    swap()

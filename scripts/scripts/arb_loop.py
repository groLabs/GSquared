import json
import os
from copy import deepcopy
from typing import Dict
from uuid import uuid4
import time

import pprint
from dotenv import load_dotenv
from eth_account import Account
from eth_account.signers.local import LocalAccount
from flashbots import flashbot
from web3 import HTTPProvider
from web3 import Web3
from web3.contract import Contract
from web3.exceptions import TransactionNotFound

pp = pprint.PrettyPrinter(indent=4)
# Addresses
ADMIN = "0xBa5ED108abA290BBdFDD88A0F022E2357349566a"
FRAX_ARB = "0x0ECD44E4531eB827DEEd394b5eEAd3DD6c25F726"
THREE_POOL_TOKEN = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490"
FRAX_STRATEGY = "0x60a6A86ad77EF672D93Db4408D65cf27Dd627050"

# Constants
CHAIN_ID = 1
AMOUNT_TO_SWAP = int(2e23)
MAX_UINT = 2**256 - 100
SLIPPAGE = 120

load_dotenv()

def load_account(web3):
    with open('./deployer') as keyfile:
        encrypted_key = keyfile.read()
    pass_ = os.getenv('deployer')
    private_key = web3.eth.account.decrypt(encrypted_key, pass_)
    return private_key


def get_abi(contract_name: str) -> Dict:
    project_root_dir = os.path.abspath(os.path.dirname(__file__))
    with open(f"./abi/{contract_name}.json") as f:
        return json.load(f)


# Ref: https://github.com/flashbots/web3-flashbots/blob/master/examples/simple.py
def swap() -> None:

    web3 = Web3(HTTPProvider(os.environ["ETH_RPC_URL"]))
    signer: LocalAccount = Account.from_key(load_account(web3))
    arb_contract: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(FRAX_ARB), abi=get_abi("FraxArb")
    )

    three_pool_token: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL_TOKEN), abi=get_abi("ERC20")
    )

    convex_strategy: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(FRAX_STRATEGY), abi=get_abi("ConvexStrategy")
    )
    flashbot(web3, signer)
    # Run the loop once as we need to decrease debtRatio of strategy
    for i in range(1):
        # Reset bundle for each arb loop
        bundle = []
        # Check if arb contract has enough 3pool tokens to perform the arb
        # If not, first transfer 3pool tokens from strategy to arb contract and then perform arb
        # If yes, perform arb without transfer, as Arb contract should already have some
        # 3pool tokens from previous arb
        three_pool_balance = three_pool_token.functions.balanceOf(
            arb_contract.address
        ).call()

        nonce = web3.eth.get_transaction_count(signer.address)
        if three_pool_balance == 0:
            # Increase allowance for 3crv token if needed before sending it to arb contract
            three_pool_allowance = three_pool_token.functions.allowance(
                ADMIN, arb_contract.address
            ).call()
            if three_pool_allowance < AMOUNT_TO_SWAP:
                tx1: TxParams = {
                        "to": three_pool_token.address,
                        "value": 0,
                        "gas": 100000,
                        "maxFeePerGas": Web3.toWei(50, "gwei"),
                        "maxPriorityFeePerGas": Web3.toWei(10, "gwei"),
                        "nonce": nonce,
                        "chainId": 1,
                        "type": 2,
                        "data": three_pool_token.encodeABI(fn_name="approve", args=[arb_contract.address, MAX_UINT]),
                }
                pp.pprint(f"tx1:\n{tx1}")
                tx_signed = signer.sign_transaction(tx1)
                nonce += 1
                #bundle.append({"signer": signer, "transaction": approve_3crv_tx})
                bundle.append({"signed_transaction": tx_signed.rawTransaction})

            tx2: TxParams = {
                    "to": arb_contract.address,
                    "value": 0,
                    "gas": 350000,
                    "maxFeePerGas": Web3.toWei(50, "gwei"),
                    "maxPriorityFeePerGas": Web3.toWei(10, "gwei"),
                    "nonce": nonce,
                    "chainId": 1,
                    "type": 2,
                    "data": arb_contract.encodeABI(fn_name="performArbWithTransfer", args=[AMOUNT_TO_SWAP]),
            }
            pp.pprint(f"tx2:\n{tx2}")
            tx2_signed = signer.sign_transaction(tx2)
            nonce += 1

            bundle.append({"signed_transaction": tx2_signed.rawTransaction})
        else:
            tx3: TxParams = {
                    "to": arb_contract.address,
                    "value": 0,
                    "gas": 350000,
                    "maxFeePerGas": Web3.toWei(50, "gwei"),
                    "maxPriorityFeePerGas": Web3.toWei(10, "gwei"),
                    "nonce": nonce,
                    "chainId": 1,
                    "type": 2,
                    "data": arb_contract.encodeABI(fn_name="performArb", args=[SLIPPAGE]),
            }
            pp.pprint(f"tx3:\n{tx3}")
            tx3_signed = signer.sign_transaction(tx3)
            nonce += 1
            bundle.append({"signed_transaction": tx3_signed.rawTransaction})

        # Run harvest in the end
        #options["to"] = convex_strategy.address
        #harvest_tx = convex_strategy.functions.runHarvest().buildTransaction(options)
        #bundle.append({"signer": signer, "transaction": harvest_tx})
        tx4: TxParams = {
                "to": convex_strategy.address,
                "value": 0,
                "gas": 350000,
                "maxFeePerGas": Web3.toWei(50, "gwei"),
                "maxPriorityFeePerGas": Web3.toWei(10, "gwei"),
                "nonce": nonce,
                "chainId": 1,
                "type": 2,
                "data": convex_strategy.encodeABI(fn_name="runHarvest", args=[]),
        }
        pp.pprint(f"tx4:\n{tx4}\n")
        tx4_signed = signer.sign_transaction(tx4)
        nonce += 1
        bundle.append({"signed_transaction": tx4_signed.rawTransaction})
        pp.pprint(bundle)
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
            print(f"tx hash: { web3.toHex(send_result.bundle_hash()) }")
            stats_v1 = web3.flashbots.get_bundle_stats(
                web3.toHex(send_result.bundle_hash()), block
            )
            stats_v2 = web3.flashbots.get_bundle_stats_v2(
                web3.toHex(send_result.bundle_hash()), block
            )
            print("bundle stats:", stats_v1)
            print("bundle stats:", stats_v2)
            send_result.wait()
            runs = 200
            while True:
                time.sleep(12)
                try:
                    receipts = send_result.receipts()
                    print(f"Bundle was mined in block {receipts[0].blockNumber}\a")
                    break
                except TransactionNotFound:
                    print(f"Bundle not found in block {web3.eth.block_number}")
                    # essentially a no-op but it shows that the function works
                    if (runs == 0):
                        cancel_res = web3.flashbots.cancel_bundles(replacement_uuid)
                        print(f"canceled {cancel_res}")
                        break;
                    else:
                        runs -= 1


if __name__ == "__main__":
    swap()

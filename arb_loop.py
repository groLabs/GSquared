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
ADMIN = '0xBa5ED108abA290BBdFDD88A0F022E2357349566a'
OUSD_ARB = '0x0000000000000000000000000000000000000000'  # TODO: Change once deployed
THREE_POOL_TOKEN = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490'
OUSD_STRATEGY = '0x73703f0493C08bA592AB1e321BEaD695AC5b39E3'
GVAULT = '0x1402c1cAa002354fC2C4a4cD2b4045A5b9625EF3'

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
    web3 = Web3(HTTPProvider("http://127.0.0.1:8545/"))
    arb_ousd: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_ARB),
        abi=get_abi("ArbOusd")
    )

    three_pool_token: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL_TOKEN),
        abi=get_abi("ERC20")
    )

    gvault: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(GVAULT),
        abi=get_abi("GVault")
    )

    convex_strategy: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_STRATEGY),
        abi=get_abi("ConvexStrategy")
    )
    # Read msig transactions from file to include them into bundle
    with open("msig_transactions.json") as f:
        msig_transactions = json.load(f)
    flashbot(web3, signer)
    print(gvault.functions.strategies(convex_strategy.address).call())
    # Run the loop 9 times as we need to decrease debtRatio of strategy
    for i in range(9):
        # Reset bundle for each arb loop
        bundle = []
        options = {
            "gas": 100000,
            "maxFeePerGas": Web3.toWei(200, "gwei"),
            "maxPriorityFeePerGas": Web3.toWei(50, "gwei"),
            "nonce": web3.eth.get_transaction_count(signer.address),
            "chainId": 31337,
            "from": signer.address,
        }
        # Increase allowance for 3crv token if needed before sending it to arb contract
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
        options_copy = deepcopy(options)
        options_copy['data'] = msig_transactions[i]['data']
        options_copy['nonce'] = web3.eth.get_transaction_count(signer.address)
        options_copy['to'] = '0x359F4fe841f246a095a82cb26F5819E10a91fe0d'
        msig_tx_signed = signer.sign_transaction(options_copy)
        tx = web3.eth.send_raw_transaction(msig_tx_signed.rawTransaction)
        print(gvault.functions.strategies(convex_strategy.address).call())
        receipt = web3.eth.wait_for_transaction_receipt(tx)
        # Execute transaction now without bundle:
        bundle.append({"signed_transaction": msig_tx_signed.rawTransaction})
        # Make sure it's successful
        assert receipt.status == 1
        options["nonce"] += 1
        # Check if arb contract has enough 3pool tokens to perform the arb
        # If not, first transfer 3pool tokens from strategy to arb contract and then perform arb
        # If yes, perform arb without transfer, as Arb contract should already have some
        # 3pool tokens from previous arb
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

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
DAO = '0x359F4fe841f246a095a82cb26F5819E10a91fe0d'
OUSD_METAPOOL = '0x87650d7bbfc3a9f10587d7778206671719d9910d'
OUSD_FLIPPER = '0xcecaD69d7D4Ed6D52eFcFA028aF8732F27e08F70'
CONVEX_OUSD = '0x73703f0493C08bA592AB1e321BEaD695AC5b39E3'
OVAULT = '0xE75D77B1865Ae93c7eaa3040B038D7aA7BC02F70'
VAULT = '0x1402c1cAa002354fC2C4a4cD2b4045A5b9625EF3'
USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
USDT = '0xdAC17F958D2ee523a2206206994597C13D831ec7'
DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
OUSD = '0x2a8e1e676ec238d8a992307b495b45b3feaa5e86'
THREE_POOL_DEPOSIT_ZAP = '0xa79828df1850e8a3a3064576f380d90aecdd3359'
THREE_POOL = '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7'

# Constants
CHAIN_ID = 1
AMOUNT_TO_SWAP = int(200_000e18)
MAX_UINT = 2 ** 256 - 100
OUSD_META_INDEX = 0
THREE_CURVE_INDEX = 1


def get_abi(contract_name: str) -> Dict:
    project_root_dir = os.path.abspath(os.path.dirname(__file__))
    with open(f"{project_root_dir}/abi/{contract_name}.json") as f:
        return json.load(f)


# Ref: https://github.com/flashbots/web3-flashbots/blob/master/examples/simple.py
def swap() -> None:
    load_dotenv()
    # signer: LocalAccount = Account.from_key(os.environ["ADMIN_KEY"])
    # web3 = Web3(HTTPProvider(os.environ["WEB3_ALCHEMY_PROJECT_ID"]))
    # # TODO: strategy.runHarvest()
    # # !! SECTION 2: Send bundle to Flashbots
    # # keep trying to send bundle until it gets mined
    # while True:
    #     block = web3.eth.block_number
    #     print(f"Simulating on block {block}")
    #     try:
    #         web3.flashbots.simulate(bundle, block)
    #         print("Simulation successful.")
    #     except Exception as e:
    #         print("Simulation error", e)
    #         return


if __name__ == "__main__":
    swap()

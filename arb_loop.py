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
    signer: LocalAccount = Account.from_key(os.environ["ADMIN_KEY"])
    web3 = Web3(HTTPProvider(os.environ["WEB3_ALCHEMY_PROJECT_ID"]))

    # !! Section 0: Setup all the contracts we'll need
    curve_ousd_metapool: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_METAPOOL),
        abi=get_abi("CurveMetapool")
    )
    usdc_erc20: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(USDC),
        abi=get_abi("ERC20")
    )
    ousd_erc20: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD),
        abi=get_abi("ERC20")
    )
    ousd_flipper: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(OUSD_FLIPPER),
        abi=get_abi("OUSDFlipper")
    )
    curve_zap: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL_DEPOSIT_ZAP),
        abi=get_abi("ThreePoolZap")
    )
    three_pool: Contract = web3.eth.contract(
        address=web3.toChecksumAddress(THREE_POOL),
        abi=get_abi("ThreePool")
    )
    flashbot(web3, signer)
    nonce = web3.eth.get_transaction_count(signer.address)
    options = {
        "gas": 100000,
        "maxFeePerGas": Web3.toWei(100, "gwei"),
        "maxPriorityFeePerGas": Web3.toWei(50, "gwei"),
        "nonce": nonce,
        "chainId": CHAIN_ID,
        "from": signer.address,
    }
    # !! SECTION 1: Build bundle of transactions to execute

    # Transactions in Flashbots are executed in order
    bundle = []
    # Build transaction to swap 3crv -> OUSD
    swap_threecurve_into_ousd_tx = curve_ousd_metapool.functions.exchange(
        THREE_CURVE_INDEX, OUSD_META_INDEX, int(AMOUNT_TO_SWAP), 0
    ).buildTransaction(options)
    bundle.append({"signer": signer, "transaction": swap_threecurve_into_ousd_tx})
    options['nonce'] += 1
    # Redeem OUSD for USDC
    # First approve OUSD to be spent by the flipper
    # Check allowance first:
    allowance = ousd_erc20.functions.allowance(signer.address, OUSD_FLIPPER).call()
    if allowance < AMOUNT_TO_SWAP:
        approve_ousd_tx = ousd_erc20.functions.approve(
            ousd_flipper.address, int(MAX_UINT)
        ).buildTransaction(options)
        bundle.append({"signer": signer, "transaction": approve_ousd_tx})
        options['nonce'] += 1
    # Then swap OUSD for USDC
    swap_ousd_into_usdc_tx = ousd_flipper.functions.sellOusdForUsdc(
        AMOUNT_TO_SWAP
    ).buildTransaction(options)
    bundle.append({"signer": signer, "transaction": swap_ousd_into_usdc_tx})
    options['nonce'] += 1
    # Deposit USDC into 3crv pool
    # First approve USDC for 3 pool
    # Check allowance first:
    usdc_allowance = usdc_erc20.functions.allowance(signer.address, three_pool.address).call()
    if usdc_allowance < AMOUNT_TO_SWAP:
        approve_usdc_tx = usdc_erc20.functions.approve(
            three_pool.address, int(MAX_UINT)
        ).buildTransaction(options)
        bundle.append({"signer": signer, "transaction": approve_usdc_tx})
        options['nonce'] += 1
    # Then deposit USDC into 3curve pool to obtain 3crv LP
    deposit_usdc_into_3crv_tx = three_pool.functions.add_liquidity(
        [0, AMOUNT_TO_SWAP, 0], 0
    ).buildTransaction(options)
    bundle.append({"signer": signer, "transaction": deposit_usdc_into_3crv_tx})
    options['nonce'] += 1
    # !! SECTION 2: Send bundle to Flashbots
    # keep trying to send bundle until it gets mined
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

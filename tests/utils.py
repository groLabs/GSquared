from typing import List

from brownie import web3

MAX_UINT256 = 2**256 - 1
YEAR_IN_SECONDS = 31556952


def move_time(add_time):
    current_ts = web3.eth.getBlock("latest").timestamp
    web3.provider.make_request("evm_setNextBlockTimestamp", [current_ts + add_time])
    web3.provider.make_request("evm_mine", [])


def error_string(custom_error: str) -> str:
    expected_revert_string = "typed error: " + web3.keccak(text=custom_error)[:4].hex()
    return expected_revert_string


def evnt_printer(txs: List[str]):
    for tx in txs:
        if not tx:
            continue
        print("--------------")
        for key, value in tx.events.items():
            if key == "Transfer":
                for event in value:
                    print(key)
                    print(event)
                continue
            print(key)
            print(value)
        print("--------------")

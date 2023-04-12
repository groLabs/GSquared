import eth_abi
from brownie import Contract, web3

from .addresses import *


def usdc():
    return Contract(USDC_ADDRESS)


def usdt():
    return Contract(USDT_ADDRESS)


def dai():
    return Contract(DAI_ADDRESS)


def mint_dai(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account, 0x2)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [DAI_ADDRESS, slot.hex(), amount]
    )


def mint_usdc(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account, 0x9)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [USDC_ADDRESS, slot.hex(), amount]
    )


def mint_usdt(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account, 0x2)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [USDT_ADDRESS, slot.hex(), amount]
    )


def E_CRV():
    return Contract(E_CRV_ADDRESS)


def FRAX_CRV():
    return Contract(FRAX_CRV_ADDRESS)


def MIM_CRV():
    return Contract(MIM_CRV_ADDRESS)


def mint_3crv(address, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["uint256", "address"], (3, address)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [E_CRV_ADDRESS, slot.hex(), amount]
    )


def mint_frax_crv(address, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["uint256", "address"], (15, address)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [FRAX_CRV_ADDRESS, slot.hex(), amount]
    )


def mint_mim_crv(address, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["uint256", "address"], (15, address)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [MIM_CRV_ADDRESS, slot.hex(), amount]
    )

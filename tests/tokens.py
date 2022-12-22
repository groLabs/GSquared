import eth_abi
import pytest
from brownie import Contract, MockDAI, MockUSDC, MockUSDT, VyperMock3CRV, web3

USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
E_CRV_ADDRESS = "0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490"
FRAX_CRV_ADDRESS = "0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B"


@pytest.fixture(scope="function", autouse=True)
def mock_dai(admin, alice):
    _mock_dai = admin.deploy(MockDAI)
    yield _mock_dai


@pytest.fixture(scope="function", autouse=True)
def mock_usdc(admin, alice):
    _mock_usdc = admin.deploy(MockUSDC)
    yield _mock_usdc


@pytest.fixture(scope="function", autouse=True)
def mock_usdt(admin, alice):
    _mock_usdt = admin.deploy(MockUSDT)
    yield _mock_usdt


@pytest.fixture(scope="function", autouse=True)
def mock_three_crv(admin):
    three_crv = admin.deploy(VyperMock3CRV, "3CRV", "3CRV", 18, 0)
    yield three_crv


@pytest.fixture(scope="function", autouse=True)
def mint_mock_token(mock_dai, mock_usdc, mock_usdt, admin, alice, bob):
    for account in [admin, alice, bob]:
        for token in [mock_dai, mock_usdc, mock_usdt]:
            token.faucet({"from": account})


@pytest.fixture(scope="function")
def usdc(admin):
    yield Contract(USDC_ADDRESS)


@pytest.fixture(scope="function")
def usdt(admin):
    yield Contract(USDT_ADDRESS)


@pytest.fixture(scope="function")
def dai(admin):
    yield Contract(DAI_ADDRESS)


@pytest.fixture(scope="function")
def E_CRV(admin):
    yield Contract(E_CRV_ADDRESS)


@pytest.fixture(scope="function")
def FRAX_CRV(admin):
    yield Contract(FRAX_CRV_ADDRESS)


def mint_dai(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account.address, 0x2)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [DAI_ADDRESS, slot.hex(), amount]
    )


def mint_usdc(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account.address, 0x9)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [USDC_ADDRESS, slot.hex(), amount]
    )


def mint_usdt(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["address", "uint256"], (account.address, 0x2)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [USDT_ADDRESS, slot.hex(), amount]
    )


def mint_3crv(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["uint256", "address"], (0x3, account.address)).hex()
    )
    hex_ = '0x' + slot.hex()[2:].lstrip('0')
    web3.provider.make_request(
        "hardhat_setStorageAt", [E_CRV_ADDRESS, hex_, amount]
    )


def mint_frax_crv(account, amount):
    amount = f"{amount:#0{66}x}"
    slot = web3.keccak(
        hexstr=eth_abi.encode_abi(["uint256", "address"], (15, account.address)).hex()
    )
    web3.provider.make_request(
        "hardhat_setStorageAt", [FRAX_CRV_ADDRESS, slot.hex(), amount]
    )

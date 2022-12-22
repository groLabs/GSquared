import pytest
from brownie import (
    ZERO_ADDRESS,
    Contract,
    GTranche,
    JuniorTranche,
    MockERC4624,
    PnL,
    PnLFixedRate,
    SeniorTranche,
    accounts,
)

LARGE_NUMBER = int(1e10)
SENIOR_TRANCHE = True
JUNIOR_TRANCHE = False
SENIOR_TRANCHE_ID = 1
JUNIOR_TRANCHE_ID = 0

token_data = {
    "test1": ["0x6B175474E89094C44Da98b954EedeAC495271d0F", "wDai", "wDai", 18],
    "test2": ["0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "wUsdc", "wUsdc", 6],
    "test3": ["0xdAC17F958D2ee523a2206206994597C13D831ec7", "wUsdt", "wUsdt", 6],
    # "test4": ["0xa47c8bf37f92aBed4A126BDA807A7b7498661acD", "wUst", "wUst", 18],
}


@pytest.fixture(scope="function")
def tranche(accounts, tokens, gTokens, mockOracle):
    tranche = accounts[0].deploy(GTranche, tokens, gTokens, mockOracle, ZERO_ADDRESS)
    gTokens[0].setController(tranche.address, {"from": accounts[0]})
    gTokens[0].addToWhitelist(tranche.address, {"from": accounts[0]})
    gTokens[1].setController(tranche.address, {"from": accounts[0]})
    gTokens[1].addToWhitelist(tranche.address, {"from": accounts[0]})
    pnl = deploy_pnl(accounts[0], tranche)
    tranche.setPnL(pnl)
    return tranche


@pytest.fixture(scope="function")
def tranche_fixed_rate(accounts, tokens, gTokens, mockOracle):
    tranche = accounts[0].deploy(GTranche, tokens, gTokens, mockOracle, ZERO_ADDRESS)
    gTokens[0].setController(tranche.address, {"from": accounts[0]})
    gTokens[0].addToWhitelist(tranche.address, {"from": accounts[0]})
    gTokens[1].setController(tranche.address, {"from": accounts[0]})
    gTokens[1].addToWhitelist(tranche.address, {"from": accounts[0]})
    pnl = deploy_pnl_fixed_rate(accounts[0], tranche)
    tranche.setPnL(pnl, {"from": accounts[0]})
    return tranche


@pytest.fixture(scope="function")
def tranche_integration(accounts, gro_vault, gTokens, oracle):
    tranche = accounts[0].deploy(GTranche, [gro_vault], gTokens, oracle, ZERO_ADDRESS)
    gTokens[0].setController(tranche.address, {"from": accounts[0]})
    gTokens[0].addToWhitelist(tranche.address, {"from": accounts[0]})
    gTokens[1].setController(tranche.address, {"from": accounts[0]})
    gTokens[1].addToWhitelist(tranche.address, {"from": accounts[0]})
    pnl = deploy_pnl_fixed_rate(accounts[0], tranche)
    tranche.setPnL(pnl, {"from": accounts[0]})
    return tranche


@pytest.fixture(scope="function")
def gTokens(accounts):
    senior = accounts[0].deploy(SeniorTranche, "senior", "snr")
    junior = accounts[0].deploy(JuniorTranche, "junior", "jnr")
    return [junior, senior]


@pytest.fixture(scope="function")
def tokens(accounts):
    gen_tokens = []
    for token, data in token_data.items():
        gen_tokens.append(deploy_token(*data))
    return gen_tokens


@pytest.fixture(scope="function")
def get_pnl(tranche):
    return Contract.from_abi(name="pnl", abi=PnL.abi, address=tranche.pnl())


@pytest.fixture(scope="function")
def get_pnl_fixed_rate(tranche_fixed_rate):
    return Contract.from_abi(
        name="pnl", abi=PnLFixedRate.abi, address=tranche_fixed_rate.pnl()
    )


def deploy_pnl(admin, tranche):
    return accounts[0].deploy(PnL, tranche)


def deploy_pnl_fixed_rate(admin, tranche):
    return accounts[0].deploy(PnLFixedRate, tranche)


def deploy_token(address, name, symbol, decimal):
    return accounts[0].deploy(MockERC4624, address, name, symbol, decimal)


def setup_token(token, amount, user, tranche):
    token.deposit(user.address, amount, {"from": user.address})
    token.approve(tranche.address, amount, {"from": user.address})


def setup_tranche(tokens, amount, users, tranche):
    txs = []
    for user in users:
        for token_index, _token in enumerate(tokens[:1]):
            _amount = amount * 10 ** _token.decimals()
            setup_token(_token, _amount, user, tranche)
            tx_1 = tranche.deposit(
                _amount / 2,
                token_index,
                JUNIOR_TRANCHE,
                user.address,
                {"from": user.address},
            )
            tx_2 = tranche.deposit(
                _amount / 4,
                token_index,
                SENIOR_TRANCHE,
                user.address,
                {"from": user.address},
            )
            txs.append(tx_1)
            txs.append(tx_2)
    return txs


def setup_tranche_all_tokens(tokens, amount, users, tranche):
    for user in users:
        for token_index, _token in enumerate(tokens[:3]):
            _amount = amount * 10 ** _token.decimals()
            setup_token(_token, _amount, user, tranche)
            tranche.deposit(
                _amount / 2,
                token_index,
                JUNIOR_TRANCHE,
                user.address,
                {"from": user.address},
            )
            tranche.deposit(
                _amount / 4,
                token_index,
                SENIOR_TRANCHE,
                user.address,
                {"from": user.address},
            )

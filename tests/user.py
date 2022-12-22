import pytest
from brownie import accounts
from utils import *

ADMIN_USER = 0
USER_1 = 1
USER_2 = 2


@pytest.fixture(scope="function", autouse=True)
def bot():
    yield accounts[1]


@pytest.fixture(scope="function", autouse=True)
def alice(gro_vault):
    yield accounts[2]


@pytest.fixture(scope="function", autouse=True)
def bob(gro_vault):
    yield accounts[3]


@pytest.fixture(scope="function", autouse=True)
def admin(accounts):
    return accounts[ADMIN_USER]


@pytest.fixture(scope="function", autouse=True)
def user_1(accounts):
    return accounts[USER_1]


@pytest.fixture(scope="function", autouse=True)
def user_2(accounts):
    return accounts[USER_2]


@pytest.fixture(scope="function", autouse=True)
def users(accounts):
    return [accounts[USER_1], accounts[USER_2]]

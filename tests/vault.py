import pytest
from brownie import GVault
from utils import *


@pytest.fixture(scope="function", autouse=True)
def gro_vault(admin, E_CRV):
    gro_vault = admin.deploy(GVault, E_CRV.address)
    yield gro_vault


@pytest.fixture(scope="function", autouse=True)
def mock_gro_vault_curve(admin, mock_three_crv):
    gro_vault = admin.deploy(GVault, mock_three_crv.address)
    yield gro_vault


@pytest.fixture(scope="function", autouse=True)
def mock_gro_vault_usdc(admin, mock_usdc):
    gro_vault = admin.deploy(GVault, mock_usdc.address)
    yield gro_vault

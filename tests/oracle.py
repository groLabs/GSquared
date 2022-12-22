import pytest
from brownie import CurveOracle, MockCurveOracle, accounts


@pytest.fixture(scope="module", autouse=True)
def mockOracle():
    return accounts[0].deploy(MockCurveOracle)


@pytest.fixture(scope="module", autouse=True)
def oracle():
    return accounts[0].deploy(CurveOracle)

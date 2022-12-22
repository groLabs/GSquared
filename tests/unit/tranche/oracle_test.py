from conftest import *

TOKEN_IDS = [0, 1]
DEPOSIT = True


def test_get_swapping_price(admin, mockOracle):
    assert (
        mockOracle.getSwappingPrice(TOKEN_IDS[0], TOKEN_IDS[1], LARGE_NUMBER, DEPOSIT)
        == LARGE_NUMBER
    )


def test_get_single_price(admin, mockOracle):
    vp = mockOracle.getVirtualPrice()
    assert (
        mockOracle.getSinglePrice(TOKEN_IDS[0], LARGE_NUMBER, DEPOSIT) == LARGE_NUMBER * vp / 1e18
    )


def test_get_total_value(admin, mockOracle):
    vp = mockOracle.getVirtualPrice()
    assert mockOracle.getTotalValue([LARGE_NUMBER]) == LARGE_NUMBER * vp / 1e18

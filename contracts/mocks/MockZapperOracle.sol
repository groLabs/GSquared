// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "../interfaces/IGRouterOracle.sol";

contract MockFixedStablecoins {
    address DAI;
    address USDC;
    address USDT;

    uint256 constant DAI_DECIMALS = 1_000_000_000_000_000_000;
    uint256 constant USDC_DECIMALS = 1_000_000;
    uint256 constant USDT_DECIMALS = 1_000_000;

    constructor() {}

    function getToken(uint256 _index) public view returns (address) {
        if (_index == 0) {
            return DAI;
        } else if (_index == 1) {
            return USDC;
        } else {
            return USDT;
        }
    }

    function getDecimal(uint256 _index) public pure returns (uint256) {
        if (_index == 0) {
            return DAI_DECIMALS;
        } else if (_index == 1) {
            return USDC_DECIMALS;
        } else {
            return USDT_DECIMALS;
        }
    }
}

contract MockZapperOracle is MockFixedStablecoins, IGRouterOracle {
    uint256 constant CHAINLINK_FACTOR = 1_00_000_000;
    uint256 constant NO_OF_AGGREGATORS = 3;
    uint256 constant STALE_CHECK = 1_0_000;

    constructor(address[3] memory stables) {
        DAI = stables[0];
        USDC = stables[1];
        USDT = stables[2];
    }

    /// @notice Get estimate USD price of a stablecoin amount
    /// @param _amount Token amount
    /// @param _index Index of token
    function stableToUsd(uint256 _amount, uint256 _index)
        external
        view
        override
        returns (uint256, bool)
    {
        return (_amount, false);
    }

    /// @notice Get LP token value of input amount of single token
    function usdToStable(uint256 _amount, uint256 _index)
        external
        view
        override
        returns (uint256, bool)
    {
        return (_amount, false);
    }
}

// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import {Relation} from "./RelationModule.sol";
import {ICurve3Pool} from "../interfaces/ICurve3Pool.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

// gro protocol: https://github.com/groLabs/GSquared
/// @title CurveOracle
/// @notice CurveOracle - Oracle defining a common denominator for the G3Crv tranche:
///     underlying tokens: G3crv - 3Crv
///     common denominator: 3Crv virtual price
///     tranche tokens priced in: 3Crv virtual price
contract CurveOracle is Relation {
    ICurve3Pool public constant curvePool =
        ICurve3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    constructor() {}

    /// @notice Get curve pool virtual price
    /// @return Value of LP-token
    function getVirtualPrice() public view returns (uint256) {
        return curvePool.get_virtual_price();
    }

    /// @notice Get swapping price between the underlying assets in
    ///     the tranche
    /// @param _i token A
    /// @param _j token B
    /// @param _amount amount of token A to swap into token B
    /// @param _deposit is the swap triggered by a deposit or withdrawal
    /// @return amount of token B
    function getSwappingPrice(
        uint256 _i,
        uint256 _j,
        uint256 _amount,
        bool _deposit
    ) external pure override returns (uint256) {
        return _amount;
    }

    /// @notice Get price of an individual underlying token
    ///     (or its relation to the whole value of the tranche)
    /// @param _i token id
    /// @param _amount amount of price
    /// @param _deposit is the pricing triggered from a deposit or a withdrawal
    /// @return price of token amount
    function getSinglePrice(
        uint256 _i,
        uint256 _amount,
        bool _deposit
    ) external view override returns (uint256) {
        return (_amount * getVirtualPrice()) / DEFAULT_FACTOR;
    }

    /// @notice Get token amount from an amount of common denominator assets
    /// @param _i index of token
    /// @param _amount amount of common denominator asset
    /// @param _deposit is the pricing triggered from a deposit or a withdrawal
    /// @return get amount of yield tokens from amount
    function getTokenAmount(
        uint256 _i,
        uint256 _amount,
        bool _deposit
    ) external view override returns (uint256) {
        return (_amount * DEFAULT_FACTOR) / getVirtualPrice();
    }

    /// @notice Get value of all underlying tokens in common denominator
    /// @param _amounts amounts of yield tokens
    /// @return total value of tokens in common denominator
    function getTotalValue(uint256[] memory _amounts)
        external
        view
        override
        returns (uint256)
    {
        uint256 total;
        uint256 vp = getVirtualPrice();
        for (uint256 i; i < _amounts.length; i++) {
            total += (_amounts[i] * vp) / DEFAULT_FACTOR;
        }
        return total;
    }
}

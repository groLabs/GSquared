// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

interface ITokenLogic {
    function balanceOfForId(
        address account,
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        uint256 balanceOfBase
    ) external view returns (uint256);

    function totalSupplyOf(
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance
    ) external view returns (uint256);

    function factor(
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        uint256 assets
    ) external view returns (uint256);

    function applyFactor(
        uint256 amount,
        uint256 factor,
        bool isFactor
    ) external pure returns (uint256);

    function convertAmount(
        uint256 tokenId,
        uint256 amount,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        bool toUnderlying
    ) external view returns (uint256);
}

library TokenCalculations {
    using SafeMath for uint256;
    uint8 public constant JUNIOR = 0;
    uint8 public constant SENIOR = 1;
    uint256 public constant BASE = 10**18;
    uint256 public constant INIT_BASE_JUNIOR = 5000000000000000;
    uint256 public constant INIT_BASE_SENIOR = 10e18;

    /// @notice Balance of account for a specific token with applied factor in case of senior tranche
    /// @param account Account address
    /// @param tokenId Token ID
    /// @param totalSupplyBase Total supply base
    /// @param trancheBalance Tranche balance
    /// @param balanceOfBase Balance of account for a specific token without applied factor
    function balanceOfForId(
        address account,
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        uint256 balanceOfBase
    ) external view returns (uint256) {
        if (tokenId == JUNIOR) {
            return balanceOfBase;
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(tokenId, totalSupplyBase, trancheBalance, 0);
            return f > 0 ? applyFactor(balanceOfBase, f, false) : 0;
        } else {
            revert("Invalid tokenId");
        }
    }

    /// @notice Calculate total supply. In case of senior, apply the factor,
    /// in case junior, return the base(raw _totalSupply)
    /// @param tokenId Token ID
    /// @param totalSupplyBase Total supply base
    /// @param trancheBalance Tranche balance
    function totalSupplyOf(
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance
    ) public view returns (uint256) {
        if (tokenId == JUNIOR) {
            return totalSupplyBase;
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(tokenId, totalSupplyBase, trancheBalance, 0);
            return f > 0 ? applyFactor(totalSupplyBase, f, false) : 0;
        } else {
            revert("Invalid tokenId");
        }
    }

    /// @notice Calculate tranche factor
    /// @param tokenId Token ID
    /// @param assets Total assets. Pass 0 to calculate from the current tranche balance
    /// @param totalSupplyBase Total supply base
    /// @param trancheBalance Tranche balance
    /// @param assets Total assets in case you want to calc factor with regards to assets
    function factor(
        uint256 tokenId,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        uint256 assets
    ) public view returns (uint256) {
        if (totalSupplyBase == 0) {
            return tokenId == SENIOR ? INIT_BASE_SENIOR : INIT_BASE_JUNIOR;
        }
        if (assets == 0) {
            assets = trancheBalance;
        }
        if (assets > 0) {
            return
                totalSupplyOf(tokenId, totalSupplyBase, trancheBalance)
                    .mul(BASE)
                    .div(assets);
        } else {
            return 0;
        }
    }

    /// @notice Apply tranche factor
    /// @param a Amount to apply factor to
    /// @param factor Factor to apply
    /// @param base true to convert to underlying, false to convert to tokens
    function applyFactor(
        uint256 a,
        uint256 factor,
        bool base
    ) internal pure returns (uint256 resultant) {
        uint256 _BASE = BASE;
        uint256 diff;
        if (base) {
            diff = a.mul(factor) % _BASE;
            resultant = a.mul(factor).div(_BASE);
        } else {
            diff = a.mul(_BASE) % factor;
            resultant = a.mul(_BASE).div(factor);
        }
        if (diff >= 5E17) {
            resultant = resultant.add(1);
        }
    }

    /// @notice Convert amount to underlying or tokens
    /// @param tokenId Token ID
    /// @param amount Amount to convert
    /// @param totalSupplyBase Total supply base
    /// @param trancheBalance Tranche balance
    /// @param toUnderlying true to convert to underlying, false to convert to tokens
    function convertAmount(
        uint256 tokenId,
        uint256 amount,
        uint256 totalSupplyBase,
        uint256 trancheBalance,
        bool toUnderlying
    ) external view returns (uint256) {
        uint256 f = factor(tokenId, totalSupplyBase, trancheBalance, 0);
        return f > 0 ? applyFactor(amount, f, toUnderlying) : 0;
    }
}

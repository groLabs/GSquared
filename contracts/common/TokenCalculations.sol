// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IGERC1155} from "../interfaces/IGERC1155.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

interface ITokenLogic {
    function balanceOfForId(
        address gerc1155,
        address account,
        uint256 tokenId
    ) external view returns (uint256);

    function totalSupplyOf(address gerc1155, uint256 tokenId)
        external
        view
        returns (uint256);

    function factor(
        address gerc1155,
        uint256 tokenId,
        uint256 assets
    ) external view returns (uint256);

    function convertAmount(
        address gerc1155,
        uint256 tokenId,
        uint256 amount,
        bool toUnderlying
    ) external view returns (uint256);
}

library TokenCalculations {
    using SafeMath for uint256;
    uint8 public constant JUNIOR = 0;
    uint8 public constant SENIOR = 1;
    uint256 public constant BASE = 1e18;
    uint256 public constant INIT_BASE_JUNIOR = 5e15;
    uint256 public constant INIT_BASE_SENIOR = 10e18;

    /// @notice Balance of account for a specific token with applied factor in case of senior tranche
    /// @param gerc1155 GERC1155 contract address
    /// @param account Account address
    /// @param tokenId Token ID
    function balanceOfForId(
        address gerc1155,
        address account,
        uint256 tokenId
    ) external view returns (uint256) {
        if (tokenId == JUNIOR) {
            return IGERC1155(gerc1155).balanceOfBase(account, tokenId);
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(gerc1155, tokenId, 0);
            return
                f > 0
                    ? applyFactor(
                        IGERC1155(gerc1155).balanceOfBase(account, tokenId),
                        f,
                        false
                    )
                    : 0;
        } else {
            revert("Invalid tokenId");
        }
    }

    /// @notice Calculate total supply. In case of senior, apply the factor,
    /// in case junior, return the base(raw _totalSupply)
    /// @param gerc1155 GERC1155 contract address
    /// @param tokenId Token ID
    function totalSupplyOf(address gerc1155, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        if (tokenId == JUNIOR) {
            return IGERC1155(gerc1155).totalSupplyBase(tokenId);
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(gerc1155, tokenId, 0);
            return
                f > 0
                    ? applyFactor(
                        IGERC1155(gerc1155).totalSupplyBase(tokenId),
                        f,
                        false
                    )
                    : 0;
        } else {
            revert("Invalid tokenId");
        }
    }

    /// @notice Calculate tranche factor
    /// @param gerc1155 GERC1155 contract address
    /// @param tokenId Token ID
    /// @param assets Total assets. Pass 0 to calculate from the current tranche balance
    function factor(
        address gerc1155,
        uint256 tokenId,
        uint256 assets
    ) public view returns (uint256) {
        if (IGERC1155(gerc1155).totalSupplyBase(tokenId) == 0) {
            return tokenId == SENIOR ? INIT_BASE_SENIOR : INIT_BASE_JUNIOR;
        }
        if (assets == 0) {
            assets = IGERC1155(gerc1155).getTrancheBalance(tokenId);
        }
        if (assets > 0) {
            return totalSupplyOf(gerc1155, tokenId).mul(BASE).div(assets);
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
    /// @param gerc1155 GERC1155 contract address
    /// @param tokenId Token ID
    /// @param amount Amount to convert
    /// @param toUnderlying true to convert to underlying, false to convert to tokens
    function convertAmount(
        address gerc1155,
        uint256 tokenId,
        uint256 amount,
        bool toUnderlying
    ) external view returns (uint256) {
        uint256 f = factor(gerc1155, tokenId, 0);
        return f > 0 ? applyFactor(amount, f, toUnderlying) : 0;
    }
}

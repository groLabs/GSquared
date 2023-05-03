// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import {ERC1155} from "../solmate/src/tokens/ERC1155.sol";
import {IGERC1155} from "../interfaces/IGERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../common/Constants.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

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
    function balanceOf(
        GERC1155 gerc1155,
        address account,
        uint256 tokenId
    ) public view returns (uint256) {
        if (tokenId == JUNIOR) {
            return gerc1155.balanceOfBase(account, tokenId);
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(gerc1155, tokenId, 0);
            return
                f > 0
                    ? applyFactor(
                        gerc1155.balanceOfBase(account, tokenId),
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
    /// @param tokenId Token ID
    function totalSupply(GERC1155 gerc1155, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        if (tokenId == JUNIOR) {
            return gerc1155.totalSupplyBase(tokenId);
        } else if (tokenId == SENIOR) {
            // If senior, apply the factor
            uint256 f = factor(gerc1155, tokenId, 0);
            return
                f > 0
                    ? applyFactor(gerc1155.totalSupplyBase(tokenId), f, false)
                    : 0;
        } else {
            revert("Invalid tokenId");
        }
    }

    /// @notice Calculate tranche factor
    /// @param tokenId Token ID
    /// @param assets Total assets. Pass 0 to calculate from the current tranche balance
    function factor(
        GERC1155 gerc1155,
        uint256 tokenId,
        uint256 assets
    ) public view returns (uint256) {
        if (gerc1155.totalSupplyBase(tokenId) == 0) {
            return
                tokenId == SENIOR
                    ? INIT_BASE_SENIOR
                    : INIT_BASE_JUNIOR;
        }
        if (assets == 0) {
            assets = gerc1155.getTrancheBalance(tokenId);
        }
        if (assets > 0) {
            return totalSupply(gerc1155, tokenId).mul(BASE).div(assets);
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
    /// @param toUnderlying true to convert to underlying, false to convert to tokens
    function convertAmount(
        GERC1155 gerc1155,
        uint256 tokenId,
        uint256 amount,
        bool toUnderlying
    ) public view returns (uint256) {
        uint256 f = factor(gerc1155, tokenId, 0);
        return f > 0 ? applyFactor(amount, f, toUnderlying) : 0;
    }
}

/// @title Gro extension of ERC1155
/// @notice Token definition contract
contract GERC1155 is ERC1155, IGERC1155, Constants {
    // Extend amount of tokens as needed

    /*///////////////////////////////////////////////////////////////
                       Storage values
    //////////////////////////////////////////////////////////////*/
    // Accounting for the total "value" (as defined in the oracle/relation module)
    //  of the tranches: True => Senior Tranche, False => Junior Tranche
    mapping(uint256 => uint256) public trancheBalances;
    mapping(uint256 => uint256) private _totalSupply;
    mapping(uint256 => uint256) public tokenBase;

    /*///////////////////////////////////////////////////////////////
                       Mint burn external logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint tokens to an address
    /// @param account The address to mint tokens to
    /// @param id The token id to mint
    /// @param amount The amount to be minted
    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) internal {
        require(account != address(0), "mint: 0x");
        require(amount > 0, "Amount is zero.");
        uint256 factoredAmount = TokenCalculations.convertAmount(
            this,
            id,
            amount,
            true
        );
        // Update the tranche supply
        _beforeTokenTransfer(
            address(0),
            account,
            _asSingletonArray(id),
            _asSingletonArray(factoredAmount)
        );

        _mint(account, id, factoredAmount, "");
    }

    /// @notice Burn tokens from an account
    /// @param account Account to burn tokens from
    /// @param id Token ID
    /// @param amount Amount to burn
    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) internal {
        require(account != address(0), "mint: 0x");
        require(amount > 0, "Amount is zero.");
        uint256 factoredAmount = TokenCalculations.convertAmount(
            this,
            id,
            amount,
            true
        );
        _beforeTokenTransfer(
            account,
            address(0),
            _asSingletonArray(id),
            _asSingletonArray(factoredAmount)
        );
        _burn(account, id, factoredAmount);
    }

    /*///////////////////////////////////////////////////////////////
                       Transfer Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer tokens from one address to another with factor taken into account
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param id The token id to transfer
    /// @param amount The amount to be transferred
    function transferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) public {
        uint256 factoredAmount = id == SENIOR
            ? TokenCalculations.convertAmount(this, id, amount, true)
            : amount;
        _beforeTokenTransfer(
            from,
            to,
            _asSingletonArray(id),
            _asSingletonArray(factoredAmount)
        );
        safeTransferFrom(from, to, id, factoredAmount, "");
    }

    /*///////////////////////////////////////////////////////////////
                       Public views
    //////////////////////////////////////////////////////////////*/

    /// @notice uri function is not used for GERC1155
    function uri(uint256 id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return "";
    }

    /// @notice Total supply of token with factor applied
    /// @param id Token ID
    function totalSupply(uint256 id) public view override returns (uint256) {
        return TokenCalculations.totalSupply(this, id);
    }

    /// @notice Total amount of tokens in with a given id without applied factor
    /// @param id Token ID
    function totalSupplyBase(uint256 id) public view override returns (uint256) {
        return tokenBase[id];
    }

    /// @notice Returns the USD balance of tranche token
    /// @param id Token ID
    function getTrancheBalance(uint256 id)
        public
        view
        virtual
        returns (uint256)
    {
        return trancheBalances[id];
    }

    /// @notice Amount of token the user owns with factor applied
    /// @param account Address of the user
    /// @param id Token ID
    function balanceOfWithFactor(address account, uint256 id)
        public
        view
        override
        returns (uint256)
    {
        return TokenCalculations.balanceOf(this, account, id);
    }

    /// @notice Amount of token the user owns without factor applied
    /// @param account Address of the user
    /// @param id Token ID
    function balanceOfBase(address account, uint256 id)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf[account][id];
    }

    /// @notice Calculate factor with respect to total assets passed in function argument
    /// @param id Token ID
    /// @param _totalAssets Total assets of the tranche
    function _calcFactor(uint256 id, uint256 _totalAssets)
        internal
        view
        returns (uint256)
    {
        return TokenCalculations.factor(this, id, _totalAssets);
    }

    /// @notice Price should always be 10**18 for Senior
    /// @param id Token ID
    function getPricePerShare(uint256 id) external view override returns (uint256) {
        uint256 _base = BASE;
        if (id == SENIOR) {
            return _base;
        } else {
            return TokenCalculations.convertAmount(this, id, _base, false);
        }
    }

    function factor(uint256 id) public view override returns (uint256) {
        return TokenCalculations.factor(this, id, trancheBalances[id]);
    }

    /*///////////////////////////////////////////////////////////////
                       Internal logic
    //////////////////////////////////////////////////////////////*/
    /// @notice Internal hook to run before any token transfer to capture changes in total supply
    /// @param from Address of the sender
    /// @param to Address of the receiver
    /// @param ids Array of token IDs
    /// @param amounts Array of token amounts
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                _totalSupply[ids[i]] += amounts[i];
            }
        }

        if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                _totalSupply[ids[i]] -= amounts[i];
            }
        }
    }

    function _asSingletonArray(uint256 element)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }
}

// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import {ERC1155} from "../solmate/src/tokens/ERC1155.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

library TokenCalculations {
    using SafeMath for uint256;
    uint256 public constant BASE = 10**18;
    uint256 public constant INIT_BASE_JUNIOR = 5000000000000000;
    uint256 public constant INIT_BASE_SENIOR = 10e18;

    function balanceOf(
        GERC1155 gerc1155,
        address account,
        uint256 tokenId
    ) public view returns (uint256) {
        if (tokenId == gerc1155.JUNIOR()) {
            return gerc1155.balanceOfBase(account, tokenId);
        } else if (tokenId == gerc1155.SENIOR()) {
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

    function totalSupply(GERC1155 gerc1155, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        if (tokenId == gerc1155.JUNIOR()) {
            return gerc1155.totalSupplyBase(tokenId);
        } else if (tokenId == gerc1155.SENIOR()) {
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
                tokenId == gerc1155.SENIOR()
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

    function applyFactor(
        uint256 a,
        uint256 b,
        bool base
    ) internal pure returns (uint256 resultant) {
        uint256 _BASE = BASE;
        uint256 diff;
        if (base) {
            diff = a.mul(b) % _BASE;
            resultant = a.mul(b).div(_BASE);
        } else {
            diff = a.mul(_BASE) % b;
            resultant = a.mul(_BASE).div(b);
        }
        if (diff >= 5E17) {
            resultant = resultant.add(1);
        }
    }

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
contract GERC1155 is ERC1155 {
    using SafeMath for uint256;
    // Extend amount of tokens as needed
    // TODO: Move to constants and derive?
    uint8 public constant JUNIOR = 0;
    uint8 public constant SENIOR = 1;

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
        super.safeTransferFrom(from, to, id, factoredAmount, "");
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

    /**
     * @dev Total amount of tokens in with a given id and applied factor in case tranche token dictates it
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return TokenCalculations.totalSupply(this, id);
    }

    function totalSupplyBase(uint256 id) public view virtual returns (uint256) {
        return tokenBase[id];
    }

    /// @notice Returns the USD balance of tranche token
    function getTrancheBalance(uint256 id)
        public
        view
        virtual
        returns (uint256)
    {
        return trancheBalances[id];
    }

    /// @notice Amount of token the user owns
    function balanceOfWithFactor(address account, uint256 id)
        public
        view
        returns (uint256)
    {
        return TokenCalculations.balanceOf(this, account, id);
    }

    function balanceOfBase(address account, uint256 id)
        public
        view
        returns (uint256)
    {
        return balanceOf[account][id];
    }

    function _calcFactor(uint256 id, uint256 _totalAssets)
        internal
        view
        returns (uint256)
    {
        return TokenCalculations.factor(this, id, _totalAssets);
    }

    /// @notice Price should always be 10**18 for Senior
    function getPricePerShare(uint256 id) external view returns (uint256) {
        uint256 _base = TokenCalculations.BASE;
        if (id == SENIOR) {
            return _base;
        } else {
            return TokenCalculations.convertAmount(this, id, _base, false);
        }
    }

    /*///////////////////////////////////////////////////////////////
                       Internal logic
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     */
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

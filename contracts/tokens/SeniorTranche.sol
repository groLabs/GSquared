// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "./GToken.sol";
import {console2} from "../../lib/forge-std/src/console2.sol";

/// @notice Rebasing token implementation of the GToken.
///     This contract defines the PWRD Stablecoin (pwrd) - A yield bearing stable coin used in
///     Gro protocol. The Rebasing token does not rebase in discrete events by minting new tokens,
///     but rather relies on the GToken factor to establish the amount of tokens in circulation,
///     in a continuous manner. The token supply is defined as:
///         BASE (10**18) / factor (total supply / total assets)
///     where the total supply is the number of minted tokens, and the total assets
///     is the USD value of the underlying assets used to mint the token.
///     For simplicity the underlying amount of tokens will be referred to as base, while
///     the rebased amount (base/factor) will be referred to as rebase.
contract SeniorTranche is GToken {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event LogTransfer(
        address indexed sender,
        address indexed recipient,
        uint256 indexed amount
    );

    constructor(string memory name, string memory symbol)
        GToken(name, symbol)
    {}

    /// @notice TotalSupply override - the totalsupply of the Rebasing token is
    ///     calculated by dividing the totalSupplyBase (standard ERC20 totalSupply)
    ///     by the factor. This result is the rebased amount
    function totalSupply() public view override returns (uint256) {
        uint256 f = factor();
        return f > 0 ? applyFactor(totalSupplyBase(), f, false) : 0;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 f = factor();
        return f > 0 ? applyFactor(balanceOfBase(account), f, false) : 0;
    }

    /// @notice Transfer override - Overrides the transfer method to transfer
    ///     the correct underlying base amount of tokens, but emit the rebased amount
    /// @param recipient Recipient of transfer
    /// @param amount Base amount to transfer
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 transferAmount = applyFactor(amount, factor(), true);
        super._transfer(msg.sender, recipient, transferAmount, amount);
        emit LogTransfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Price should always be 1E18
    function getPricePerShare() external view override returns (uint256) {
        return BASE;
    }

    function getShareAssets(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return shares;
    }

    function getAssets(address account)
        external
        view
        override
        returns (uint256)
    {
        return balanceOf(account);
    }

    /// @notice calculate USD value of a set amount of Tranche tokens
    /// @param amount Amount of Tranche token
    /// Note: for Senior tranch amount is already denominated in common denominator
    /// @return USD value of amount
    function getTokenAssets(uint256 amount)
        public
        view
        override
        returns (uint256)
    {
        return amount;
    }

    /// @notice calculate amount of Tranche tokens for a set USD(or any other commonly denominated) value
    /// @param assets USD(or any other commonly denominated) value
    /// Note: for Senior tranch amount is already denominated in common denominator
    /// @return Amount of Tranche tokens
    function getTokenAmountFromAssets(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return assets;
    }

    /// @notice Mint RebasingGTokens
    /// @param account Target account
    /// @param amount Mint amount in USD
    function mint(address account, uint256 amount)
        external
        override
        onlyWhitelist
    {
        require(account != address(0), "mint: 0x");
        require(amount > 0, "Amount is zero.");
        uint256 balance = trancheBalance();
        // Apply factor to amount to get rebase amount
        uint256 mintAmount = applyFactor(amount, factor(), true);
        // Increase $ tranche balance before minting
        _setTrancheBalance(balance + amount);
        _mint(account, mintAmount, amount);
    }

    /// @notice Burn RebasingGTokens
    /// @param account Target account
    /// @param amount Burn amount in USD
    function burn(address account, uint256 amount)
        external
        override
        onlyWhitelist
    {
        require(account != address(0), "burn: 0x");
        require(amount > 0, "Amount is zero.");
        uint256 balance = trancheBalance();
        // Apply factor to amount to get rebase amount
        uint256 burnAmount = applyFactor(amount, factor(), true);
        _setTrancheBalance(balance - amount);
        _burn(account, burnAmount, amount);
    }

    /// @notice Burn all pwrds for account - used by withdraw all methods
    /// @param account Target account
    function burnAll(address account) external override onlyWhitelist {
        require(account != address(0), "burnAll: 0x");
        uint256 burnAmount = balanceOfBase(account);
        uint256 amount = applyFactor(burnAmount, factor(), false);
        // Apply factor to amount to get rebase amount
        _burn(account, burnAmount, amount);
    }

    /// @notice transferFrom override - Overrides the transferFrom method
    ///     to transfer the correct amount of underlying tokens (Base amount)
    ///     but emit the rebased amount
    /// @param sender Sender of transfer
    /// @param recipient Reciepient of transfer
    /// @param amount Mint amount in USD
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        super._decreaseApproved(sender, msg.sender, amount);
        uint256 transferAmount = applyFactor(amount, factor(), true);
        super._transfer(sender, recipient, transferAmount, amount);
        return true;
    }
}

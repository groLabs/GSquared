// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "./GToken.sol";

/// @notice NonRebasing token implementation of the GToken.
///     This contract defines the Gro Vault Token (GVT) - A yield bearing token used in
///     gro protocol. The NonRebasing token has a fluctuating price, defined as:
///         BASE (10**18) / factor (total supply / total assets)
///     where the total supply is the number of minted tokens, and the total assets
///     is the USD value of the underlying assets used to mint the token.
contract JuniorTranche is GToken {
    // uint256 public constant INIT_BASE = 3333333333333333;
    uint256 public constant INIT_BASE = 5000000000000000;

    using SafeERC20 for IERC20;

    event LogTransfer(
        address indexed sender,
        address indexed recipient,
        uint256 indexed amount,
        uint256 factor
    );

    constructor(string memory name, string memory symbol)
        GToken(name, symbol)
    {}

    /// @notice Return the base supply of the token - This is similar
    ///     to the original ERC20 totalSupply method for NonRebasingGTokens
    function totalSupply() public view override returns (uint256) {
        return totalSupplyBase();
    }

    /// @notice Amount of token the user owns
    function balanceOf(address account) public view override returns (uint256) {
        return balanceOfBase(account);
    }

    /// @notice Transfer override - does the same thing as the standard
    ///     ERC20 transfer function (shows number of tokens transferred)
    /// @param recipient Recipient of transfer
    /// @param amount Amount to transfer
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        super._transfer(msg.sender, recipient, amount, amount);
        emit LogTransfer(msg.sender, recipient, amount, factor());
        return true;
    }

    /// @notice Price per token (USD)
    function getPricePerShare() public view override returns (uint256) {
        uint256 f = factor();
        return f > 0 ? applyFactor(BASE, f, false) : 0;
    }

    /// @notice Price of a set amount of shared
    /// @param shares Number of shares
    function getShareAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return applyFactor(shares, getPricePerShare(), true);
    }

    /// @notice Get amount USD value of users assets
    /// @param account Target account
    function getAssets(address account)
        external
        view
        override
        returns (uint256)
    {
        return getShareAssets(balanceOf(account));
    }

    /// @notice calculate USD value of a set amount of Tranche tokens
    /// @param amount Amount of Tranche token
    /// @return USD value of amount
    function getTokenAssets(uint256 amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 f = factor();
        return f > 0 ? applyFactor(amount, f, false) : 0;
    }

    /// @notice calculate amount of Tranche tokens for a set USD(or any other commonly denominated) value
    /// @param assets USD(or any other commonly denominated) value
    /// @return Amount of Tranche tokens
    function getTokenAmountFromAssets(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return applyFactor(assets, factor(), true);
    }

    function getInitialBase() internal pure override returns (uint256) {
        return INIT_BASE;
    }

    /// @notice Mint NonRebasingGTokens
    /// @param account Target account
    /// @param amount Mint amount in USD
    /// @param totalTrancheValue Total value of tranche in USD - amount
    function mint(
        address account,
        uint256 amount,
        uint256 totalTrancheValue
    ) external override onlyWhitelist {
        require(account != address(0), "mint: 0x");
        require(amount > 0, "Amount is zero.");
        // Divide USD amount by factor to get number of tokens to mint
        uint256 mintAmount = applyFactor(amount, factor(), true);
        _setTrancheBalance(totalTrancheValue + amount);
        _mint(account, mintAmount, amount);
    }

    /// @notice Burn NonRebasingGTokens
    /// @param account Target account
    /// @param amount Burn amount in USD
    /// @param totalTrancheValue Total value of tranche in USD - amount
    function burn(
        address account,
        uint256 amount,
        uint256 totalTrancheValue
    ) external override onlyWhitelist {
        require(account != address(0), "burn: 0x");
        require(amount > 0, "Amount is zero.");
        // Apply factor to amount to get rebase amount
        uint256 burnAmount = applyFactor(amount, factor(), true);
        // Set new tranche balance before burning
        _setTrancheBalance(totalTrancheValue - amount);
        _burn(account, burnAmount, amount);
    }

    /// @notice Burn all tokens for user (used by withdraw all methods to avoid dust)
    /// @param account Target account
    function burnAll(address account) external override onlyWhitelist {
        require(account != address(0), "burnAll: 0x");
        uint256 amount = balanceOfBase(account);
        _burn(account, amount, amount);
    }
}

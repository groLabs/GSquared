// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGTranche.sol";
import "../interfaces/IOracle.sol";
import "../utils/FixedTokens.sol";
import "../GMigration.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

// gro protocol: https://github.com/groLabs/GSquared

/// @title GTranche
/// @notice GTranche - Lego block for handling tranching
///
///     ###############################################
///     GTranche Specification
///     ###############################################
///
///     The GTranche provides a novel way for insurance to be implemented on the blockchain,
///         allowing for users who seek a safer yield opportunity (senior tranche) to do so by
///         providing part of their deposit as leverage for an insurer (junior tranche). Which
///         is done by distributing parts of the yield generated by underlying tokens based
///         on the demand for insurance (utilisation ratio).
///     This version of the tranche takes advantage of the new tokenized vault standard
///     (https://eips.ethereum.org/EIPS/eip-4626) and acts as a wrapper for 4626 token in
///     order to generate and distribute yield.
///
///     This contract is one part of two required to define a tranche:
///         1) GTranche module - defines a set of tokens, and handles accounting
///             and yield distribution between the Senior and Junior tranche.
///         2) oracle/relation module - defines the relation between the tokens in
///             the tranche
///
///     The following logic is covered in the GTranche contract:
///         - Deposit:
///             - User deposits takes an EIP-4626 token and evaluates it to a common denominator,
///                which indicates the value of their deposit and the number of tranche tokens
///                that get minted
///         - Withdrawal:
///             - User withdrawals takes tranche tokens and evaluates their value to EIP-4626 tokens,
///                which indicates the number of tokens that should be returned to the user
///                on withdrawal
///         - PnL:
///             - User interactions evaluates the latest price per share of the underlying
///                4626 compatible tokens, effectively handling front-running of gains/losses.
///                Its important that the underlying EIP-4626 cannot be price manipulated, as this
///                would break the pnl functionality of this contract.
contract GTrancheGeneric is IGTranche, FixedTokens, Ownable {
    /*//////////////////////////////////////////////////////////////
                        CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    // Module defining relations between underlying assets
    IOracle public immutable oracle;
    GMigration private immutable gMigration;

    /*//////////////////////////////////////////////////////////////
                    STORAGE VARIABLES & TYPES
    //////////////////////////////////////////////////////////////*/

    // SENIOR / JUNIOR Tranche
    uint256 public utilisationThreshold = 5000;
    bool public hasMigratedFromOldTranche;
    address newGTranche;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LogNewDeposit(
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 indexed index,
        bool indexed tranche
    );

    event LogNewWithdrawal(
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 indexed index,
        bool indexed tranche
    );

    event LogNewRatio(uint256 newRatio);

    event LogMigration(
        uint256 JuniorTrancheBalance,
        uint256 SeniorTrancheBalance,
        uint256[] YieldTokenBalances
    );

    event LogMigration(
        uint256 oldJuniorTrancheBalance,
        uint256 oldSeniorTrancheBalance
    );

    event LogMigrationPrepared(address newGTranche);
    event LogMigrationFinished(address newGTranche);

    constructor(
        address[] memory _yieldTokens,
        address[2] memory _trancheTokens,
        address _oracle,
        GMigration _gMigration
    ) FixedTokens(_yieldTokens, _trancheTokens) {
        oracle = IOracle(_oracle);
        gMigration = _gMigration;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the threshold for when utilisation will prohibit deposit
    ///     from the senior tranche, or withdrawals for the junior
    /// @param _newRatio target utilisation ratio
    function setUtilisationRatio(uint256 _newRatio) external onlyOwner {
        utilisationThreshold = _newRatio;
        emit LogNewRatio(_newRatio);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Handles deposit logic for GTranche:
    ///     User deposits underlying yield tokens which values get calculated
    ///     to a common denominator used to price the tranches in. This operation
    ///     relies on the existence of a relation/oracle module that allows this
    ///     contract to establish a relation between the underlying yield tokens.
    ///     Any unearned profit will be realized before the tokens are minted,
    ///     effectively stopping the user from front-running profit.
    /// @param _amount amount of yield token user deposits
    /// @param _index index of yield token deposited
    /// @param _tranche tranche user wishes to go into
    /// @param _recipient recipient of tranche tokens
    /// @dev this function will revert if a senior tranche deposit makes the utilisation
    ///     exceed the utilisation ratio
    function deposit(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256, uint256) {
        ERC4626 token = ERC4626(getYieldToken(_index));
        token.transferFrom(msg.sender, address(this), _amount);

        // update value of current tranches - this prevents front-running of profits
        (uint256 _utilisation, uint256 calc_amount) = updateDistribution(
            _amount,
            _index,
            _tranche,
            false
        );
        if (_tranche)
            require(_utilisation <= utilisationThreshold, "!utilisation");
        tokenBalances[_index] += _amount;
        IGToken trancheToken = getTrancheToken(_tranche);
        uint256 factor = trancheToken.factor();
        trancheToken.mint(_recipient, factor, calc_amount);
        emit LogNewDeposit(msg.sender, _recipient, _amount, _index, _tranche);
        uint256 trancheAmount;
        if (_tranche) trancheAmount = calc_amount;
        else trancheAmount = (calc_amount * factor) / DEFAULT_FACTOR;
        return (trancheAmount, calc_amount);
    }

    /// @notice Handles withdrawal logic:
    ///     User redeems an amount of tranche token for underlying yield tokens, any loss/profit
    ///     will be realized before the tokens are burned, effectively stopping the user from
    ///     front-running losses or lose out on gains when redeeming
    /// @param _amount amount of tranche tokens to redeem
    /// @param _index index of yield token the user wishes to withdraw
    /// @param _tranche tranche user wishes to redeem
    /// @param _recipient recipient of the yield tokens
    /// @dev this function will revert if a senior tranche deposit makes the utilisation
    function withdraw(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256, uint256) {
        IGToken trancheToken = getTrancheToken(_tranche);

        require(_amount <= trancheToken.balanceOf(msg.sender), "balance");
        // get factor before changing total assets
        uint256 factor = trancheToken.factor();

        // update value of current tranches - this prevents front-running of losses
        (uint256 _utilisation, uint256 calc_amount) = updateDistribution(
            _amount,
            _index,
            _tranche,
            true
        );
        if (!_tranche)
            require(_utilisation <= utilisationThreshold, "!utilisation");

        uint256 yieldTokenAmounts = _calcTokenAmount(
            _index,
            calc_amount,
            false
        );
        tokenBalances[_index] -= yieldTokenAmounts;

        trancheToken.burn(msg.sender, factor, calc_amount);

        ERC4626(getYieldToken(_index)).transfer(msg.sender, yieldTokenAmounts);

        emit LogNewWithdrawal(
            msg.sender,
            _recipient,
            _amount,
            _index,
            _tranche
        );
        return (yieldTokenAmounts, calc_amount);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current utilisation ratio of the tranche in BP
    function utilisation() external view returns (uint256) {
        uint256[NO_OF_TRANCHES] memory _totalValue = _calcTotalValue();
        return (_totalValue[1] * DEFAULT_DECIMALS) / (_totalValue[0] + 1);
    }

    /// @notice Update the current assets in the Junior/Senior tranche by
    ///     taking the change in value of the underlying yield token into account since
    ///     the previous interaction and distributing these based on the profit
    ///     distribution curve.
    /// @param _amount value of deposit/withdrawal
    /// @param _index index of yield token
    /// @param _tranche senior or junior tranche being deposited/withdrawn
    /// @param _withdraw withdrawal or deposit
    function updateDistribution(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        bool _withdraw
    ) internal returns (uint256, uint256) {
        uint256 calc_amount;
        uint256[NO_OF_TRANCHES] memory _totalValue = pnlDistribution();
        if (_withdraw) {
            calc_amount = _tranche
                ? _amount
                : _calcTrancheValue(_tranche, _amount, _totalValue[0]);
            if (_tranche) _totalValue[1] -= calc_amount;
            else _totalValue[0] -= calc_amount;
        } else {
            calc_amount = _calcTokenValue(_index, _amount, true);
            if (_tranche) _totalValue[1] += calc_amount;
            else _totalValue[0] += calc_amount;
        }
        trancheBalances[SENIOR_TRANCHE_ID] = _totalValue[1];
        trancheBalances[JUNIOR_TRANCHE_ID] = _totalValue[0];

        uint256 _utilisation = (_totalValue[1] * DEFAULT_DECIMALS) /
            (_totalValue[0] + 1);
        emit LogNewTrancheBalance(_totalValue, _utilisation);
        return (_utilisation, calc_amount);
    }

    /// @notice Calculate the changes in underlying token value and distribute profit
    function pnlDistribution()
        public
        view
        returns (uint256[NO_OF_TRANCHES] memory _trancheBalances)
    {
        uint256 totalValue = _calcUnfiedValue();
        _trancheBalances[0] = trancheBalances[JUNIOR_TRANCHE_ID];
        _trancheBalances[1] = trancheBalances[SENIOR_TRANCHE_ID];
        uint256 currentTotal = _trancheBalances[0] + _trancheBalances[1];
        if (currentTotal > totalValue) {
            if (currentTotal - totalValue > _trancheBalances[0]) {
                _trancheBalances[1] -=
                    currentTotal -
                    totalValue -
                    _trancheBalances[0];
                _trancheBalances[0] = 0;
            } else {
                _trancheBalances[0] -= currentTotal - totalValue;
            }
        } else if (currentTotal < totalValue) {
            uint256 _utilisation = (_trancheBalances[1] * DEFAULT_DECIMALS) /
                (_trancheBalances[0] + 1);
            uint256[NO_OF_TRANCHES] memory profits = _distributeProfit(
                totalValue - currentTotal,
                _utilisation
            );
            _trancheBalances[0] += profits[0];
            _trancheBalances[1] += profits[1];
        }
    }

    // TODO update default profit distribution curve
    /// @notice Calculate distribution of changes of underlying yield tokens
    /// @param _amount amount to distribute
    /// @param _utilisation current utilisation between senior/junior tranche
    function _distributeProfit(uint256 _amount, uint256 _utilisation)
        internal
        pure
        returns (uint256[NO_OF_TRANCHES] memory profit)
    {
        uint256 seniorProfit = (_amount * _utilisation) / DEFAULT_DECIMALS;
        uint256 juniorProfit = _amount - seniorProfit;

        if (_utilisation > 10000) _utilisation = 10000;
        else if (_utilisation < 8000)
            _utilisation = (_utilisation * 3) / 8 + 3000;
        else _utilisation = (_utilisation - 8000) * 2 + 6000;

        uint256 profitFromSeniorTranche = (seniorProfit * _utilisation) / 10000;
        profit[0] = juniorProfit + profitFromSeniorTranche;
        profit[1] = seniorProfit - profitFromSeniorTranche;
    }

    /*//////////////////////////////////////////////////////////////
                        Price/Value logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current total value of tranches
    function _calcTotalValue()
        internal
        view
        returns (uint256[NO_OF_TRANCHES] memory trancheAssets)
    {
        return pnlDistribution();
    }

    /// @notice Calculate the price of the underlying yield token
    /// @param _index index of yield token
    /// @param _amount amount of yield tokens
    /// @param _deposit is the transaction a deposit or a withdrawal
    function _calcTokenValue(
        uint256 _index,
        uint256 _amount,
        bool _deposit
    ) internal view returns (uint256) {
        return
            oracle.getSinglePrice(
                _index,
                getYieldTokenValue(_index, _amount),
                _deposit
            );
    }

    /// @notice Calculate the number of tokens for the given amount
    /// @param _index index of yield token
    /// @param _amount amount of yield tokens
    /// @param _deposit is the transaction a deposit or a withdrawal
    function _calcTokenAmount(
        uint256 _index,
        uint256 _amount,
        bool _deposit
    ) internal view returns (uint256) {
        return
            getYieldTokenAmount(
                _index,
                oracle.getTokenAmount(_index, _amount, _deposit)
            );
    }

    /// @notice Calculate the value of an amount of tranche tokens
    /// @param _tranche junior or senior tranche
    /// @param _amount amount of yield tokens
    function _calcTrancheValue(bool _tranche, uint256 _amount)
        internal
        view
        returns (uint256)
    {}

    /// @notice Calculate the value of all underlying yield tokens
    function _calcUnfiedValue() internal view returns (uint256 totalValue) {
        uint256[NO_OF_TOKENS] memory yieldTokenValues = getYieldTokenValues();
        uint256[] memory tokenValues = new uint256[](NO_OF_TOKENS);
        for (uint256 i; i < NO_OF_TOKENS; ++i) {
            tokenValues[i] = yieldTokenValues[i];
        }
        totalValue = oracle.getTotalValue(tokenValues);
    }

    /*//////////////////////////////////////////////////////////////
                        Migration LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Migrates funds from the old gro protocol
    /// @dev Can only be run once and from the gMigration contract
    function migrateFromOldTranche() external onlyOwner {
        require(!hasMigratedFromOldTranche, "Already Migrated");

        // only one token in the initial version of the GTranche
        uint256 token_index = NO_OF_TOKENS - 1;
        ERC4626 token = ERC4626(getYieldToken(token_index));

        uint256[] memory yieldTokenShares = new uint256[](NO_OF_TOKENS);
        uint256 _shares = token.balanceOf(address(gMigration));
        yieldTokenShares[token_index] = _shares;
        uint256 seniorDollarAmount = gMigration.seniorTrancheDollarAmount();

        // calculate yield token shares for seniorDollarAmount
        uint256 seniorShares = _calcTokenAmount(0, seniorDollarAmount, true);
        // get the amount of shares per tranche
        uint256 juniorShares = _shares - seniorShares;

        // calculate $ value of each tranche
        uint256 juniorValue = _calcTokenValue(0, juniorShares, true);
        uint256 seniorValue = _calcTokenValue(0, seniorShares, true);

        // update tranche $ balances
        trancheBalances[SENIOR_TRANCHE_ID] += seniorValue;
        trancheBalances[JUNIOR_TRANCHE_ID] += juniorValue;

        // update yield token balances
        tokenBalances[0] += _shares;
        hasMigratedFromOldTranche = true;

        token.transferFrom(address(gMigration), address(this), _shares);

        updateDistribution(0, 0, true, false);

        emit LogMigration(juniorValue, seniorValue, yieldTokenShares);
    }

    /// @notice Set the target for the migration
    /// @dev This should be kept behind a timelock as the address could be any EOA
    ///    which could drain funds. This function should ultimately be removed
    /// @param _newGTranche address of new GTranche
    function prepareMigration(address _newGTranche) external onlyOwner {
        newGTranche = _newGTranche;
        emit LogMigrationPrepared(_newGTranche);
    }

    /// @notice Transfer funds and update Tranches values
    /// @dev Updates the state of the tranche post migration.
    ///     This function should ultimately be removed
    function finalizeMigration() external override {
        require(msg.sender == newGTranche, "insert custom error here");
        ERC4626 token;
        for (uint256 index; index < NO_OF_TOKENS; index++) {
            token = getYieldToken(index);
            token.transfer(msg.sender, token.balanceOf(address(this)));
            tokenBalances[index] = token.balanceOf(address(this));
        }
        updateDistribution(0, 0, true, false);
        emit LogMigrationFinished(msg.sender);
    }

    /// @notice Migrate assets from old GTranche to new GTranche
    /// @dev Assumes same mapping of yield tokens but you can have more at increased indexes
    ///     in the new tranche. This function should be behind a timelock.
    /// @param _oldGTranche address of the old GTranche
    function migrate(address _oldGTranche) external onlyOwner {
        GTranche oldTranche = GTranche(_oldGTranche);
        uint256 oldSeniorTrancheBalance = oldTranche.trancheBalances(true);
        uint256 oldJuniorTrancheBalance = oldTranche.trancheBalances(false);

        trancheBalances[SENIOR_TRANCHE_ID] += oldSeniorTrancheBalance;
        trancheBalances[JUNIOR_TRANCHE_ID] += oldJuniorTrancheBalance;

        uint256[] memory yieldTokenBalances = new uint256[](
            oldTranche.NO_OF_TOKENS()
        );

        oldTranche.finalizeMigration();

        uint256 oldBalance;
        uint256 currentBalance;
        for (uint256 index; index < NO_OF_TOKENS; index++) {
            ERC4626 token = ERC4626(getYieldToken(index));
            oldBalance = tokenBalances[index];
            currentBalance = token.balanceOf(address(this));
            tokenBalances[index] = currentBalance;
            yieldTokenBalances[index] = currentBalance - oldBalance;
        }

        updateDistribution(0, 0, true, false);

        emit LogMigration(
            trancheBalances[JUNIOR_TRANCHE_ID],
            trancheBalances[SENIOR_TRANCHE_ID],
            yieldTokenBalances
        );
    }

    /*//////////////////////////////////////////////////////////////
                        Legacy logic (GTokens)
    //////////////////////////////////////////////////////////////*/

    /// @notice This function exists to support the older versions of the GToken
    ///     return value of underlying token based on caller
    function gTokenTotalAssets() external view returns (uint256) {
        uint256[NO_OF_TRANCHES] memory _totalValue = pnlDistribution();
        if (msg.sender == JUNIOR_TRANCHE) return _totalValue[0];
        else if (msg.sender == SENIOR_TRANCHE) return _totalValue[1];
        else return _totalValue[0] + _totalValue[1];
    }

    /// @notice Calculate the number of tokens for the given amount
    /// @param _tranche junior or senior tranche
    /// @param _amount amount to transform to tranche tokens
    /// @param _total total value in tranche
    function _calcTrancheValue(
        bool _tranche,
        uint256 _amount,
        uint256 _total
    ) internal view returns (uint256) {
        uint256 factor = getTrancheToken(_tranche).factor(_total);
        return (_amount * DEFAULT_FACTOR) / factor;
    }

    /// @notice Legacy calculation of tranche tokens base factor
    /// @param _tranche junior or senior tranche
    function _tranche_base(bool _tranche) internal pure returns (uint256) {
        return _tranche ? DEFAULT_FACTOR : DEFAULT_FACTOR;
    }
}

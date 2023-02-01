// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGTranche} from "./interfaces/IGTranche.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IPnL} from "./interfaces/IPnL.sol";
import {ERC4626} from "./tokens/ERC4626.sol";
import {Errors} from "./common/Errors.sol";
import {FixedTokensCurve} from "./utils/FixedTokensCurve.sol";
import {GMigration} from "./GMigration.sol";
import {IGToken} from "./interfaces/IGToken.sol";

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
///         on the demand for insurance (utilization ratio).
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
contract GTranche is IGTranche, FixedTokensCurve, Ownable {
    /*//////////////////////////////////////////////////////////////
                        CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    // Module defining relations between underlying assets
    IOracle public immutable oracle;
    // Migration contract
    GMigration private immutable gMigration;
    uint256 public constant minDeposit = 1e18;

    /*//////////////////////////////////////////////////////////////
                    STORAGE VARIABLES & TYPES
    //////////////////////////////////////////////////////////////*/

    // SENIOR / JUNIOR Tranche
    uint256 public utilisationThreshold = 10000;
    IPnL public pnl;

    bool public hasMigratedFromOldTranche;
    address newGTranche;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LogNewDeposit(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 index,
        bool indexed tranche,
        uint256 calcAmount
    );

    event LogNewWithdrawal(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 index,
        bool indexed tranche,
        uint256 yieldTokenAmounts,
        uint256 calcAmount
    );

    event LogNewUtilizationThreshold(uint256 newThreshold);
    event LogNewPnL(int256 profit, int256 loss);

    event LogMigration(
        uint256 JuniorTrancheBalance,
        uint256 SeniorTrancheBalance,
        uint256[] YieldTokenBalances
    );

    event LogSetNewPnLLogic(address pnl);
    event LogMigrationPrepared(address newGTranche);
    event LogMigrationFinished(address newGTranche);

    constructor(
        address[] memory _yieldTokens,
        address[2] memory _tranchTokens,
        IOracle _oracle,
        GMigration _gMigration
    ) FixedTokensCurve(_yieldTokens, _tranchTokens) {
        oracle = _oracle;
        gMigration = _gMigration;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the threshold for when utilization will prohibit deposit
    ///     from the senior tranche, or withdrawals for the junior
    /// @param _newThreshold target utilization threshold
    function setUtilizationThreshold(uint256 _newThreshold) external onlyOwner {
        utilisationThreshold = _newThreshold;
        emit LogNewUtilizationThreshold(_newThreshold);
    }

    /// @notice Set the pnl logic of the tranche
    /// @param _pnl new pnl logic
    function setPnL(IPnL _pnl) external onlyOwner {
        pnl = _pnl;
        emit LogSetNewPnLLogic(address(_pnl));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW LOGIC
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
    /// @return trancheAmount amount of tranche tokens minted
    /// @return calcAmount value of tranche token in common denominator (USD)
    /// @dev this function will revert if a senior tranche deposit makes the utilization
    ///     exceed the utilization ratio
    function deposit(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256 trancheAmount, uint256 calcAmount) {

        ERC4626 token = ERC4626(getYieldToken(_index));
        token.transferFrom(msg.sender, address(this), _amount);

        IGToken trancheToken = getTrancheToken(_tranche);

        uint256 factor;
        uint256 trancheUtilization;

        // update value of current tranches - this prevents front-running of profits
        (trancheUtilization, calcAmount, factor) = updateDistribution(
            _amount,
            _index,
            _tranche,
            false
        );

        if (calcAmount < minDeposit) {
            revert("GTranche: deposit amount too low");
        }
        if (_tranche && trancheUtilization > utilisationThreshold) {
            revert Errors.UtilisationTooHigh();
        }

        tokenBalances[_index] += _amount;
        trancheToken.mint(_recipient, factor, calcAmount);
        emit LogNewDeposit(
            msg.sender,
            _recipient,
            _amount,
            _index,
            _tranche,
            calcAmount
        );
        if (_tranche) trancheAmount = calcAmount;
        else trancheAmount = calcAmount * factor / DEFAULT_FACTOR;
        return (trancheAmount, calcAmount);
    }

    /// @notice Handles withdrawal logic:
    ///     User redeems an amount of tranche token for underlying yield tokens, any loss/profit
    ///     will be realized before the tokens are burned, effectively stopping the user from
    ///     front-running losses or lose out on gains when redeeming
    /// @param _amount amount of tranche tokens to redeem
    /// @param _index index of yield token the user wishes to withdraw
    /// @param _tranche tranche user wishes to redeem
    /// @param _recipient recipient of the yield tokens
    /// @return yieldTokenAmounts amount of underlying tokens withdrawn
    /// @return calcAmount value of tranche token in common denominator (USD)
    /// @dev this function will revert if a senior tranche deposit makes the utilization
    function withdraw(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    )
        external
        override
        returns (uint256 yieldTokenAmounts, uint256 calcAmount)
    {
        IGToken trancheToken = getTrancheToken(_tranche);

        if (_amount > trancheToken.balanceOf(msg.sender)) {
            revert Errors.NotEnoughBalance();
        }
        ERC4626 token = ERC4626(getYieldToken(_index));

        uint256 factor; // = _calcFactor(_tranche);
        uint256 trancheUtilization;

        // update value of current tranches - this prevents front-running of losses
        (trancheUtilization, calcAmount, factor) = updateDistribution(
            _amount,
            _index,
            _tranche,
            true
        );

        if (!_tranche && trancheUtilization > utilisationThreshold) {
            revert Errors.UtilisationTooHigh();
        }

        yieldTokenAmounts = _calcTokenAmount(_index, calcAmount, false);
        tokenBalances[_index] -= yieldTokenAmounts;

        trancheToken.burn(msg.sender, factor, calcAmount);
        token.transfer(_recipient, yieldTokenAmounts);

        emit LogNewWithdrawal(
            msg.sender,
            _recipient,
            _amount,
            _index,
            _tranche,
            yieldTokenAmounts,
            calcAmount
        );
        return (yieldTokenAmounts, calcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current utilization ratio of the tranche in BP
    function utilization() external view returns (uint256) {
        (uint256[NO_OF_TRANCHES] memory _totalValue, , ) = pnlDistribution();
        if (_totalValue[1] == 0) return 0;
        return _totalValue[0] > 0 ? (_totalValue[1] * DEFAULT_DECIMALS) / (_totalValue[0]) : type(uint256).max;
    }

    /// @notice Update the current assets in the Junior/Senior tranche by
    ///     taking the change in value of the underlying yield token into account since
    ///     the previous interaction and distributing these based on the profit
    ///     distribution curve.
    /// @param _amount value of deposit/withdrawal
    /// @param _index index of yield token
    /// @param _tranche senior or junior tranche being deposited/withdrawn
    /// @param _withdraw withdrawal or deposit
    /// @return trancheUtilization current utilization of the two tranches (senior / junior)
    /// @return calcAmount value of tranche token in common denominator (USD)
    function updateDistribution(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        bool _withdraw
    )
        internal
        returns (
            uint256 trancheUtilization,
            uint256 calcAmount,
            uint256 factor
        )
    {
        (
            uint256[NO_OF_TRANCHES] memory _totalValue,
            int256 profit,
            int256 loss
        ) = _pnlDistribution();

        factor = _tranche
            ? _calcFactor(_tranche, _totalValue[1])
            : _calcFactor(_tranche, _totalValue[0]);
        if (_withdraw) {
            calcAmount = _tranche
                ? _amount
                : _calcTrancheValue(_tranche, _amount, factor, _totalValue[0]);
            if (_tranche) _totalValue[1] -= calcAmount;
            else _totalValue[0] -= calcAmount;
        } else {
            calcAmount = _calcTokenValue(_index, _amount, true);
            if (_tranche) _totalValue[1] += calcAmount;
            else _totalValue[0] += calcAmount;
        }
        trancheBalances[SENIOR_TRANCHE_ID] = _totalValue[1];
        trancheBalances[JUNIOR_TRANCHE_ID] = _totalValue[0];

        if (_totalValue[1] == 0) trancheUtilization = 0;
        else trancheUtilization = _totalValue[0] > 0 ? (_totalValue[1] * DEFAULT_DECIMALS) / (_totalValue[0]) : type(uint256).max;
        emit LogNewTrancheBalance(_totalValue, trancheUtilization);
        emit LogNewPnL(profit, loss);
        return (trancheUtilization, calcAmount, factor);
    }

    /// @notice View of current asset distribution
    function pnlDistribution()
        public
        view
        returns (
            uint256[NO_OF_TRANCHES] memory newTrancheBalances,
            int256 profit,
            int256 loss
        )
    {
        int256[NO_OF_TRANCHES] memory _trancheBalances;
        int256 totalValue = int256(_calcUnifiedValue());
        _trancheBalances[0] = int256(trancheBalances[JUNIOR_TRANCHE_ID]);
        _trancheBalances[1] = int256(trancheBalances[SENIOR_TRANCHE_ID]);
        int256 lastTotal = _trancheBalances[0] + _trancheBalances[1];
        if (lastTotal > totalValue) {
            loss = lastTotal - totalValue;
            int256[NO_OF_TRANCHES] memory losses = pnl.distributeLoss(
                loss,
                _trancheBalances
            );
            _trancheBalances[0] -= losses[0];
            _trancheBalances[1] -= losses[1];
        } else {
            profit = totalValue - lastTotal;
            int256[NO_OF_TRANCHES] memory profits = pnl.distributeProfit(
                profit,
                _trancheBalances
            );
            _trancheBalances[0] += profits[0];
            _trancheBalances[1] += profits[1];
        }
        newTrancheBalances[0] = uint256(_trancheBalances[0]);
        newTrancheBalances[1] = uint256(_trancheBalances[1]);
    }

    /// @notice Calculate the changes in underlying token value and distribute profit
    function _pnlDistribution()
        internal
        returns (
            uint256[NO_OF_TRANCHES] memory newTrancheBalances,
            int256 profit,
            int256 loss
        )
    {
        int256[NO_OF_TRANCHES] memory _trancheBalances;
        int256 totalValue = int256(_calcUnifiedValue());
        _trancheBalances[0] = int256(trancheBalances[JUNIOR_TRANCHE_ID]);
        _trancheBalances[1] = int256(trancheBalances[SENIOR_TRANCHE_ID]);
        int256 lastTotal = _trancheBalances[0] + _trancheBalances[1];
        if (lastTotal > totalValue) {
            loss = lastTotal - totalValue;
            int256[NO_OF_TRANCHES] memory losses = pnl.distributeAssets(
                true,
                loss,
                _trancheBalances
            );
            _trancheBalances[0] -= losses[0];
            _trancheBalances[1] -= losses[1];
        } else {
            profit = totalValue - lastTotal;
            int256[NO_OF_TRANCHES] memory profits = pnl.distributeAssets(
                false,
                profit,
                _trancheBalances
            );
            _trancheBalances[0] += profits[0];
            _trancheBalances[1] += profits[1];
        }
        newTrancheBalances[0] = uint256(_trancheBalances[0]);
        newTrancheBalances[1] = uint256(_trancheBalances[1]);
    }

    /*//////////////////////////////////////////////////////////////
                        Price/Value logic
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Calculate the number of yield token for the given amount
    /// @param _index index of yield token
    /// @param _amount amount to convert to yield tokens
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

    /// @notice Calculate the value of all underlying yield tokens
    function _calcUnifiedValue() internal view returns (uint256 totalValue) {
        uint256[NO_OF_TOKENS] memory yieldTokenValues = getYieldTokenValues();
        uint256[] memory tokenValues = new uint256[](NO_OF_TOKENS);
        for (uint256 i; i < NO_OF_TOKENS; i++) {
            tokenValues[i] = yieldTokenValues[i];
        }
        totalValue = oracle.getTotalValue(tokenValues);
    }

    /*//////////////////////////////////////////////////////////////
                        Migration LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Migrates funds from the old gro protocol
    /// @dev Can only be run once and is and intermediary step to move assets
    ///     from gro-protocol to GSquared. This function is ultimately going to
    ///     be removed from newer iterations of this smart contract as it serves
    ///     no purpose for new tranches.
    function migrateFromOldTranche() external onlyOwner {
        if (hasMigratedFromOldTranche) {
            revert Errors.AlreadyMigrated();
        }

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
        if (msg.sender != newGTranche) revert Errors.MsgSenderNotTranche();
        ERC4626 token;
        for (uint256 index = 0; index < NO_OF_TOKENS; index++) {
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
        for (uint256 index = 0; index < NO_OF_TOKENS; index++) {
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

    uint256 internal constant JUNIOR_INIT_BASE = 5000000000000000;

    /// @notice This function exists to support the older versions of the GToken
    ///     return value of underlying token based on caller
    function gTokenTotalAssets() external view returns (uint256) {
        (uint256[NO_OF_TRANCHES] memory _totalValue, , ) = pnlDistribution();
        if (msg.sender == JUNIOR_TRANCHE) return _totalValue[0];
        else if (msg.sender == SENIOR_TRANCHE) return _totalValue[1];
        else return _totalValue[0] + _totalValue[1];
    }

    /// @notice calculate the number of tokens for the given amount
    /// @param _tranche junior or senior tranche
    /// @param _amount amount of transform to tranche tokens
    /// @param _factor xxx
    /// @param _total total value in tranche
    function _calcTrancheValue(
        bool _tranche,
        uint256 _amount,
        uint256 _factor,
        uint256 _total
    ) internal view returns (uint256 amount) {
        if (_factor == 0) revert Errors.NoAssets();
        amount = (_amount * DEFAULT_FACTOR) / _factor;
        if (amount > _total) return _total;
        return amount;
    }

    function _calcFactor(bool _tranche, uint256 _totalAssets)
        internal
        view
        returns (uint256 factor)
    {
        IGToken trancheToken = getTrancheToken(_tranche);
        uint256 init_base = _tranche ? DEFAULT_FACTOR : JUNIOR_INIT_BASE;
        uint256 supply = trancheToken.totalSupplyBase();

        if (supply == 0) {
            return init_base;
        }

        if (_totalAssets > 0) {
            return (supply * DEFAULT_FACTOR) / _totalAssets;
        }
    }
}

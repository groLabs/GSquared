// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import {Owned} from "./solmate/src/auth/Owned.sol";
import {IGTranche} from "./interfaces/IGTranche.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IPnL} from "./interfaces/IPnL.sol";
import {ERC4626} from "./tokens/ERC4626.sol";
import {GERC1155} from "./tokens/GERC1155.sol";
import {Errors} from "./common/Errors.sol";
import {FixedTokensCurve} from "./utils/FixedTokensCurve.sol";
import {ITokenLogic} from "./common/TokenCalculations.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
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
contract GTranche is IGTranche, GERC1155, FixedTokensCurve, Owned {
    /*//////////////////////////////////////////////////////////////
                        CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    // Module defining relations between underlying assets
    IOracle public immutable oracle;

    uint256 public constant minDeposit = 1e18;

    /*//////////////////////////////////////////////////////////////
                    STORAGE VARIABLES & TYPES
    //////////////////////////////////////////////////////////////*/

    // SENIOR / JUNIOR Tranche
    uint256 public utilisationThreshold = 10000;
    IPnL public pnl;

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

    event LogNewUtilisationThreshold(uint256 newThreshold);
    event LogNewPnL(int256 profit, int256 loss);

    event LogSetNewPnLLogic(address pnl);

    constructor(
        address[] memory _yieldTokens,
        IOracle _oracle,
        ITokenLogic tokenLogic
    ) FixedTokensCurve(_yieldTokens) Owned(msg.sender) GERC1155(tokenLogic) {
        require(address(tokenLogic) != address(0), "!Zero address");
        oracle = _oracle;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the threshold for when utilisation will prohibit deposit
    ///     from the senior tranche, or withdrawals for the junior
    /// @param _newThreshold target utilisation threshold
    function setUtilisationThreshold(uint256 _newThreshold) external onlyOwner {
        utilisationThreshold = _newThreshold;
        emit LogNewUtilisationThreshold(_newThreshold);
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
    /// @dev this function will revert if a senior tranche deposit makes the utilisation
    ///     exceed the utilisation ratio
    function deposit(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address _recipient
    ) external override returns (uint256 trancheAmount, uint256 calcAmount) {
        console2.log("DEPOSIT!");
        ERC4626 token = getYieldToken(_index);
        token.transferFrom(msg.sender, address(this), _amount);

        uint256 factor;
        uint256 trancheUtilisation;

        // update value of current tranches - this prevents front-running of profits
        (trancheUtilisation, calcAmount, factor) = updateDistribution(
            _amount,
            _index,
            _tranche,
            false
        );

        if (calcAmount < minDeposit) {
            revert("GTranche: deposit amount too low");
        }
        if (_tranche && trancheUtilisation > utilisationThreshold) {
            revert Errors.UtilisationTooHigh();
        }

        tokenBalances[_index] += _amount;
        mint(_recipient, _tranche ? SENIOR : JUNIOR, calcAmount);
        emit LogNewDeposit(
            msg.sender,
            _recipient,
            _amount,
            _index,
            _tranche,
            calcAmount
        );
        if (_tranche) trancheAmount = calcAmount;
        else trancheAmount = (calcAmount * factor) / DEFAULT_FACTOR;
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
    /// @dev this function will revert if a senior tranche deposit makes the utilisation
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
        if (
            _amount >
            balanceOfWithFactor(msg.sender, _tranche ? SENIOR : JUNIOR)
        ) {
            revert Errors.NotEnoughBalance();
        }
        ERC4626 token = getYieldToken(_index);

        uint256 factor;
        uint256 trancheUtilisation;

        // update value of current tranches - this prevents front-running of losses
        (trancheUtilisation, calcAmount, factor) = updateDistribution(
            _amount,
            _index,
            _tranche,
            true
        );

        if (!_tranche && trancheUtilisation > utilisationThreshold) {
            revert Errors.UtilisationTooHigh();
        }

        yieldTokenAmounts = _calcTokenAmount(_index, calcAmount, false);
        tokenBalances[_index] -= yieldTokenAmounts;

        burn(_recipient, _tranche ? SENIOR : JUNIOR, calcAmount);
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

    /// @notice Get the current utilisation ratio of the tranche in BP
    function utilisation() external view returns (uint256) {
        (uint256[NO_OF_TRANCHES] memory _totalValue, , ) = pnlDistribution();
        if (_totalValue[1] == 0) return 0;
        return
            _totalValue[0] > 0
                ? (_totalValue[1] * DEFAULT_DECIMALS) / (_totalValue[0])
                : type(uint256).max;
    }

    /// @notice Update the current assets in the Junior/Senior tranche by
    ///     taking the change in value of the underlying yield token into account since
    ///     the previous interaction and distributing these based on the profit
    ///     distribution curve.
    /// @param _amount value of deposit/withdrawal
    /// @param _index index of yield token
    /// @param _tranche senior or junior tranche being deposited/withdrawn
    /// @param _withdraw withdrawal or deposit
    /// @return trancheUtilisation current utilisation of the two tranches (senior / junior)
    /// @return calcAmount value of tranche token in common denominator (USD)
    /// @return factor factor applied to the tranche token
    function updateDistribution(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        bool _withdraw
    )
        internal
        returns (
            uint256 trancheUtilisation,
            uint256 calcAmount,
            uint256 factor
        )
    {
        (
            uint256[NO_OF_TRANCHES] memory _totalValue,
            int256 profit,
            int256 loss
        ) = _pnlDistribution();
        console2.log("Here");
        factor = _tranche
            ? _calcFactor(_tranche ? SENIOR : JUNIOR, _totalValue[1])
            : _calcFactor(_tranche ? SENIOR : JUNIOR, _totalValue[0]);
        console2.log("Here1");
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
        trancheBalances[SENIOR] = _totalValue[1];
        trancheBalances[JUNIOR] = _totalValue[0];

        if (_totalValue[1] == 0) trancheUtilisation = 0;
        else
            trancheUtilisation = _totalValue[0] > 0
                ? (_totalValue[1] * DEFAULT_DECIMALS) / (_totalValue[0])
                : type(uint256).max;
        emit LogNewTrancheBalance(_totalValue, trancheUtilisation);
        emit LogNewPnL(profit, loss);
        return (trancheUtilisation, calcAmount, factor);
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
        _trancheBalances[0] = int256(trancheBalances[JUNIOR]);
        _trancheBalances[1] = int256(trancheBalances[SENIOR]);
        int256 lastTotal = _trancheBalances[0] + _trancheBalances[1];
        if (lastTotal > totalValue) {
            unchecked {
                loss = lastTotal - totalValue;
            }
            int256[NO_OF_TRANCHES] memory losses = pnl.distributeLoss(
                loss,
                _trancheBalances
            );
            _trancheBalances[0] -= losses[0];
            _trancheBalances[1] -= losses[1];
        } else {
            unchecked {
                profit = totalValue - lastTotal;
            }
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
        _trancheBalances[0] = int256(trancheBalances[JUNIOR]);
        _trancheBalances[1] = int256(trancheBalances[SENIOR]);
        int256 lastTotal = _trancheBalances[0] + _trancheBalances[1];
        if (lastTotal > totalValue) {
            unchecked {
                loss = lastTotal - totalValue;
            }
            int256[NO_OF_TRANCHES] memory losses = pnl.distributeAssets(
                true,
                loss,
                _trancheBalances
            );
            _trancheBalances[0] -= losses[0];
            _trancheBalances[1] -= losses[1];
        } else {
            unchecked {
                profit = totalValue - lastTotal;
            }
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
        for (uint256 i; i < NO_OF_TOKENS; ++i) {
            tokenValues[i] = yieldTokenValues[i];
        }
        totalValue = oracle.getTotalValue(tokenValues);
    }

    /*//////////////////////////////////////////////////////////////
                        Legacy logic (GTokens)
    //////////////////////////////////////////////////////////////*/

    /// @notice calculate the number of tokens for the given amount
    /// @param _tranche junior or senior tranche
    /// @param _amount amount to transform to tranche tokens
    /// @param _factor factor applied to tranche token
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
}

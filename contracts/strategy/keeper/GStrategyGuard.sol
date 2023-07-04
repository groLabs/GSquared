// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "../../interfaces/IStrategy.sol";
import "../../interfaces/IGStrategyGuard.sol";
import "../../interfaces/AggregatorV3Interface.sol";
import "../../interfaces/ICurve3Pool.sol";
import "../../GVault.sol";

library GuardErrors {
    error NotOwner(); // 0x30cd7471
    error NotKeeper(); // 0xf512b278
    error StrategyNotInQueue();
}

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

// gro protocol: https://github.com/groLabs/gro-strategies-brownie

/// @title Strategy guard
/// @notice Contract that interacts with strategies, determining when harvest and stop loss should
///     be triggered. These actions dont need to be individually strategies specified as the time
///     sensitivity of the action isnt critical to the point where it needs to be executed within
///     1 block of the action has been green lit. As long as it gets triggered within a set period of time,
///     this should not block further execution of other strategies, simplifying the keeper setup
///     that will run these jobs.
contract GStrategyGuard is IGStrategyGuard {
    event LogOwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event LogKeeperSet(address newKeeper);
    event LogKeeperRemoved(address keeper);
    event LogStrategyAdded(address indexed strategy, uint256 timeLimit);
    event LogStrategyRemoved(address indexed strategy);
    event LogStrategyStatusUpdated(address indexed strategy, bool status);
    event LogStrategyStopLossPrimer(
        address indexed strategy,
        uint128 primerTimeStamp
    );
    event LogStrategyQueueReset(address[] strategies);
    event LogStopLossEscalated(address strategy);
    event LogStopLossDescalated(address strategy, bool active);
    event LogStopLossExecuted(address strategy, bool success);
    event LogStrategyHarvestFailure(
        address strategy,
        string reason,
        bytes lowLevelData
    );

    uint256 public constant TARGET_DECIMALS = 18;
    uint256 public constant LOSS_BLOCK_THRESHOLD = 25;
    AggregatorV3Interface public constant CL_ETH_USD =
        AggregatorV3Interface(
            address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)
        );
    ICurve3Pool public constant THREE_CURVE_POOL =
        ICurve3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    // 3 million gas to execute harvest
    uint256 public gasThreshold = 3_000_000;
    address public owner;
    mapping(address => bool) public keepers;

    struct strategyData {
        bool active; // Is the strategy active
        bool canHarvestWithLoss;  // Flag to indicate if the strategy can harvest with loss
        uint256 lossStartBlock;  // First block when loss occured
        uint64 timeLimit;
        uint64 primerTimestamp; // The time at which the health threshold was broken
    }

    address[] public strategies;

    // maps a strategy to its stop loss data
    mapping(address => strategyData) public strategyCheck;

    constructor() {
        owner = msg.sender;
    }

    /// @notice set a new owner for the contract
    /// @param _newOwner owner to swap to
    function setOwner(address _newOwner) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        address previousOwner = msg.sender;
        owner = _newOwner;
        emit LogOwnershipTransferred(previousOwner, _newOwner);
    }

    /// @notice set a new gas threshold for the contract to use when checking canHarvest
    /// @param _newGasThreshold gas threshold to swap to
    function setGasThreshold(uint256 _newGasThreshold) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        gasThreshold = _newGasThreshold;
    }

    /// @notice set a new keeper for the contract
    /// @param _newKeeper address of new keeper
    function setKeeper(address _newKeeper) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        keepers[_newKeeper] = true;
        emit LogKeeperSet(_newKeeper);
    }

    /// @notice remove a keeper from the contract
    /// @param _keeper address of keeper to remove
    function revokKeeper(address _keeper) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        keepers[_keeper] = false;
        emit LogKeeperRemoved(_keeper);
    }

    /// @notice forcefully sets the order of the strategies listened to
    /// @param _strategies array of strategies - these strategies must have been added previously
    /// @dev used to clear out the queue from zero addresses, be careful when using this
    function setStrategyQueue(address[] calldata _strategies) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        address[] memory _oldQueue = strategies;
        delete strategies;
        for (uint256 i; i < _strategies.length; ++i) {
            for (uint256 j; j < _oldQueue.length; ++j) {
                if (_strategies[i] == _oldQueue[j]) {
                    strategies.push(_strategies[i]);
                    break;
                }
                revert GuardErrors.StrategyNotInQueue();
            }
        }
        emit LogStrategyQueueReset(_strategies);
    }

    /// @notice Add a strategy to the stop loss logic - Needed in order to be
    ///     be able to determine health of strategies underlying investments (meta pools)
    /// @param _strategy the target strategy
    /// @param _timeLimit amount of time that needs to pass before triggering stop loss
    function addStrategy(address _strategy, uint64 _timeLimit) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        _addStrategy(_strategy);
        strategyCheck[_strategy].timeLimit = _timeLimit;
        strategyCheck[_strategy].active = true;

        emit LogStrategyAdded(_strategy, _timeLimit);
    }

    /// @notice Check if strategy already has been added, if not
    ///     add it to the list of strategies
    function _addStrategy(address _strategy) internal {
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            if (strategies[i] == _strategy) {
                return;
            }
        }
        strategies.push(_strategy);
    }

    /// @notice Remove strategy from stop loss logic
    /// @param _strategy address of strategy
    function removeStrategy(address _strategy) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        delete strategyCheck[_strategy];
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            if (strategies[i] == _strategy) {
                strategies[i] = address(0);
            }
        }

        emit LogStrategyRemoved(_strategy);
    }

    /// @notice Activate/Deactivate strategy
    /// @param _strategy the target strategy
    /// @param _status set status of strategy
    function updateStrategyStatus(address _strategy, bool _status) external {
        if (msg.sender != owner) revert GuardErrors.NotOwner();
        if (_strategy == address(0)) return;
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == _strategy) {
                strategyCheck[strategy].active = _status;
                emit LogStrategyStatusUpdated(_strategy, _status);
                return;
            }
        }
    }

    /// @notice Check if stop loss primer needs to be triggered for a strategy
    function canUpdateStopLoss() external view returns (bool result) {
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (IStrategy(strategy).canStopLoss()) {
                if (
                    strategyCheck[strategy].primerTimestamp == 0 &&
                    strategyCheck[strategy].active
                ) {
                    result = true;
                }
            }
        }
    }

    /// @notice Check if stop loss primer needs to be stopped
    function canEndStopLoss() external view returns (bool result) {
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (!IStrategy(strategy).canStopLoss()) {
                if (
                    strategyCheck[strategy].primerTimestamp != 0 &&
                    strategyCheck[strategy].active
                ) {
                    result = true;
                }
            }
        }
    }

    /// @notice Check if stop loss needs to be executed
    function canExecuteStopLossPrimer() external view returns (bool result) {
        uint256 strategiesLength = strategies.length;
        address strategy;
        uint64 primerTimestamp;
        for (uint256 i; i < strategiesLength; i++) {
            strategy = strategies[i];
            primerTimestamp = strategyCheck[strategy].primerTimestamp;
            if (primerTimestamp == 0) continue;
            if (IStrategy(strategy).canStopLoss()) {
                if (
                    block.timestamp - primerTimestamp >=
                    strategyCheck[strategy].timeLimit &&
                    strategyCheck[strategy].active
                ) {
                    result = true;
                }
            }
        }
    }

    /// @notice Check if any strategy with loss can be unlocked
    /// @return canExec true if a strategy can be unlocked
    /// @return execPayload payload to execute
    function canUnlockLoss()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        uint256 strategiesLength = strategies.length;

        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            uint256 excessDebt = _getExcessDebt(IStrategy(strategy));
            if (
                excessDebt > 0 &&
                strategyCheck[strategy].canHarvestWithLoss == false &&
                strategyCheck[strategy].lossStartBlock != 0 &&
                strategyCheck[strategy].lossStartBlock + LOSS_BLOCK_THRESHOLD <
                block.number
            ) {
                execPayload = abi.encodeWithSelector(this.unlockLoss.selector, (strategy));
                canExec = true;
                break;
            } else if (
                excessDebt == 0 && strategyCheck[strategy].lossStartBlock != 0
            ) {

                execPayload = abi.encodeWithSelector(
                    this.resetLossStartBlock.selector,
                    (strategy)
                );
                canExec = true;
                break;
            }
        }
    }

    /// @notice Update the stop loss primer by setting a stop loss start time for a strategy
    function setStopLossPrimer() external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (IStrategy(strategy).canStopLoss()) {
                if (
                    strategyCheck[strategy].primerTimestamp == 0 &&
                    strategyCheck[strategy].active
                ) {
                    strategyCheck[strategy].primerTimestamp = uint64(
                        block.timestamp
                    );
                    emit LogStopLossEscalated(strategy);
                    return;
                }
            }
        }
    }

    /// @notice Cancel the stop loss by resetting the stop loss start time for a strategy
    function endStopLossPrimer() external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (!IStrategy(strategy).canStopLoss()) {
                if (
                    strategyCheck[strategy].primerTimestamp != 0 &&
                    strategyCheck[strategy].active
                ) {
                    strategyCheck[strategy].primerTimestamp = 0;
                    emit LogStopLossDescalated(strategy, true);
                    return;
                }
            }
        }
    }

    /// @notice Execute stop loss for a given strategy
    function executeStopLoss() external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        uint256 strategiesLength = strategies.length;
        address strategy;
        uint256 primerTimestamp;
        for (uint256 i; i < strategiesLength; i++) {
            strategy = strategies[i];
            primerTimestamp = strategyCheck[strategy].primerTimestamp;
            if (primerTimestamp == 0 || strategy == address(0)) continue;
            if (IStrategy(strategy).canStopLoss()) {
                if (
                    (block.timestamp - primerTimestamp) >=
                    strategyCheck[strategy].timeLimit &&
                    strategyCheck[strategy].active
                ) {
                    bool success = IStrategy(strategy).stopLoss();
                    emit LogStopLossExecuted(strategy, success);
                    if (success) {
                        strategyCheck[strategy].primerTimestamp = 0;
                        strategyCheck[strategy].active = false;
                        emit LogStopLossDescalated(strategy, false);
                    }
                    return;
                }
            }
        }
    }

    /// @notice Function that converts _amount of ETH to USD using CL ETH/USD pricefeed
    /// @notice It also scales the price to 18 decimals as ETH/USD feed has non 18 decimals
    /// @param _amount the amount of ETH to convert
    function _convertETHToUSD(uint256 _amount) internal view returns (uint256) {
        (, int256 ethPriceInUsd, , , ) = CL_ETH_USD.latestRoundData();
        // Scale the price to 18 decimals
        uint256 ethPriceInWei = uint256(ethPriceInUsd) *
            10**(TARGET_DECIMALS - CL_ETH_USD.decimals());
        return (_amount * ethPriceInWei) / 10**TARGET_DECIMALS;
    }

    /// @notice Check if harvest needs to be executed for a strategy
    /// @param strategy the target strategy
    function _profitOrLossExceeded(IStrategy strategy)
        internal
        view
        returns (bool)
    {
        bool canHarvest;
        uint256 assets = strategy.estimatedTotalAssets();
        GVault vault = GVault(strategy.vault());

        (, , , uint256 totalDebt, , ) = vault.strategies(address(strategy));

        uint256 debt = totalDebt;
        (uint256 excessDebt, ) = vault.excessDebt(address(strategy));
        uint256 profit;
        if (assets > debt) {
            profit = assets - debt;
        } else {
            excessDebt += debt - assets;
        }
        // If there is excess debt we should harvest anyway
        if (excessDebt > 0) {
            canHarvest = true;
        }
        profit += vault.creditAvailable(address(strategy));
        // Check if profit exceeds the gas threshold
        uint256 gasUsedForHarvestInUsd = _convertETHToUSD(
            tx.gasprice * gasThreshold
        );
        uint256 profitInUsd = (THREE_CURVE_POOL.get_virtual_price() * profit) /
            10**TARGET_DECIMALS;
        if (profitInUsd > gasUsedForHarvestInUsd) {
            canHarvest = true;
        }
        return canHarvest;
    }

    /// @notice Calculate the excess debt for a strategy
    /// @param strategy - the target strategy
    function _getExcessDebt(IStrategy strategy)
        internal
        view
        returns (uint256)
    {
        GVault vault = GVault(strategy.vault());
        (, , , uint256 totalDebt, , ) = vault.strategies(address(strategy));
        uint256 assets = strategy.estimatedTotalAssets();
        uint256 debt = totalDebt;
        (uint256 excessDebt, ) = vault.excessDebt(address(strategy));
        excessDebt += debt - assets;
        return excessDebt;
    }

    /// @notice Check if any strategy needs to be harvested
    function canHarvest() external view returns (bool result) {
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (
                IStrategy(strategy).canHarvest() &&
                _profitOrLossExceeded(IStrategy(strategy))
            ) {
                if (strategyCheck[strategy].active) {
                    result = true;
                }
            }
        }
    }

    /// @notice Unlock canHarvestWithLoss for strategy
    /// @param strategy the target strategy
    function unlockLoss(address strategy) external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        strategyCheck[strategy].canHarvestWithLoss = true;
    }

    /// @notice Reset lossStartBlock for strategy plus resets canHarvestWithLoss
    /// @param strategy the target strategy
    function resetLossStartBlock(address strategy) external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        _resetLossStartBlock(strategy);
    }

    /// @notice Reset lossStartBlock for strategy plus resets canHarvestWithLoss
    /// @param strategy the target strategy
    function _resetLossStartBlock(address strategy) private {
        strategyCheck[strategy].lossStartBlock = 0;
        // Set canHarvestWithLoss to false as well
        strategyCheck[strategy].canHarvestWithLoss = false;
    }

    /// @notice Execute strategy harvest
    function harvest() external {
        if (!keepers[msg.sender]) revert GuardErrors.NotKeeper();
        uint256 strategiesLength = strategies.length;
        for (uint256 i; i < strategiesLength; ++i) {
            address strategy = strategies[i];
            if (strategy == address(0)) continue;
            if (IStrategy(strategy).canHarvest()) {
                if (strategyCheck[strategy].active) {
                    // Record the start block of the loss and don't allow to run with canHarvestWithLoss unless
                    // It's explicitly allowed
                    if (
                        _getExcessDebt(IStrategy(strategy)) > 0 &&
                        !strategyCheck[strategy].canHarvestWithLoss &&
                        strategyCheck[strategy].lossStartBlock == 0
                    ) {
                        strategyCheck[strategy].lossStartBlock = block.number;
                        return;
                    }
                    IStrategy(strategy).runHarvest();
                    // Reset loss related storage variables so next time we can do checks again
                    _resetLossStartBlock(strategy);
                    return;
                }
            }
        }
    }
}

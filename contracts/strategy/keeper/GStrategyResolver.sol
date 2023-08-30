// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import {Owned} from "../../solmate/src/auth/Owned.sol";
import "../../interfaces/IGStrategyGuard.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

// gro protocol: https://github.com/groLabs/GSquared

/// @title GStopLossResolver
/// @notice Targets GStopLossExecutor contract to update/reset primer values
/// alongside this triggering a strategy stop loss if primer interval threshold
/// is met.
contract GStopLossResolver is Owned {
    address immutable stopLossExecutor;

    constructor(address _stopLossExecutor) Owned(msg.sender) {
        stopLossExecutor = _stopLossExecutor;
    }

    /// @notice returns correct payload to gelato to update strategy
    /// stop loss primer on the GStopLossExecutor
    function taskUpdateStopLossPrimer()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IGStrategyGuard executor = IGStrategyGuard(stopLossExecutor);
        if (executor.canUpdateStopLoss()) {
            canExec = true;
            execPayload = abi.encodeWithSelector(
                executor.setStopLossPrimer.selector
            );
        }
    }

    /// @notice returns correct payload to gelato to stop the strategy
    /// stop loss primer on the GStopLossExecutor
    function taskStopStopLossPrimer()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IGStrategyGuard executor = IGStrategyGuard(stopLossExecutor);
        if (executor.canEndStopLoss()) {
            canExec = true;
            execPayload = abi.encodeWithSelector(
                executor.endStopLossPrimer.selector
            );
        }
    }

    /// @notice returns function selector to gelato to unlock loss OR set lossStartBlock to 0 for the
    /// first strategy that was locked with a loss
    function taskCanUnlockLoss()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IGStrategyGuard executor = IGStrategyGuard(stopLossExecutor);
        (canExec, execPayload) = executor.canUnlockStrategy();
    }

    /// @notice returns correct payload to gelato to trigger strategy
    /// stop loss on the GStopLossExecutor
    function taskTriggerStopLoss()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IGStrategyGuard executor = IGStrategyGuard(stopLossExecutor);
        if (executor.canExecuteStopLossPrimer()) {
            canExec = true;
            execPayload = abi.encodeWithSelector(
                executor.executeStopLoss.selector
            );
        }
    }

    /// @notice returns correct payload to gelato to trigger Strategy Harvest
    function taskStrategyHarvest()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        IGStrategyGuard executor = IGStrategyGuard(stopLossExecutor);
        if (executor.canHarvest()) {
            canExec = true;
            execPayload = abi.encodeWithSelector(executor.harvest.selector);
        }
    }
}

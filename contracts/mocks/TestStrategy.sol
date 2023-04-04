// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategy.sol";

/*
 * This Strategy serves as both a mock Strategy for testing, and an example
 * for integrators on how to use BaseStrategy
 */

contract TestStrategy is BaseStrategy {
    bool public doReentrancy;
    bool public ammStatus = true;
    bool noLoss = false;
    bool tooMuchGain = false;
    bool tooMuchLoss = false;

    constructor(address _vault) BaseStrategy(_vault) {}

    function name() external pure override returns (string memory) {
        return "TestStrategy";
    }

    // NOTE: This is a test-only function to simulate losses
    function _takeFunds(uint256 amount) public {
        want.transfer(msg.sender, amount);
    }

    // NOTE: This is a test-only function to enable reentrancy on withdraw
    function _toggleReentrancyExploit() public {
        doReentrancy = !doReentrancy;
    }

    function estimatedTotalAssets() external view override returns (uint256) {
        // For mock, this is just everything we have
        return _estimatedTotalAssets();
    }

    function _prepareReturn(uint256 _excessDebt)
        internal
        view
        returns (
            uint256 profit,
            uint256 loss,
            uint256 debtPayment
        )
    {
        // During testing, send this contract some tokens to simulate "Rewards"
        uint256 totalAssets = want.balanceOf(address(this));
        uint256 totalDebt = vault.getStrategyDebt();
        if (totalAssets > _excessDebt) {
            debtPayment = _excessDebt;
            totalAssets -= _excessDebt;
        } else {
            debtPayment = totalAssets;
            totalAssets = 0;
        }
        totalDebt -= debtPayment;

        if (totalAssets > totalDebt) {
            profit = totalAssets - totalDebt;
        } else {
            loss = totalDebt - totalAssets;
        }
        if (tooMuchGain) {
            profit = profit * 5;
        }
        if (tooMuchLoss) {
            loss = totalDebt * 2;
        }
    }

    function _adjustPosition(uint256 _excessDebt) internal {
        // Whatever we have "free", consider it "invested" now
    }

    function setTooMuchGain() external {
        tooMuchGain = true;
    }

    function setTooMuchLoss() external {
        tooMuchLoss = true;
    }

    function setNoLossStrategy() external {
        noLoss = true;
    }

    function _liquidatePosition(uint256 _amountNeeded)
        internal
        view
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 totalDebt = vault.getStrategyDebt();
        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            liquidatedAmount = totalAssets;
            if (!noLoss) {
                loss = _amountNeeded - totalAssets;
            }
        } else {
            // NOTE: Just in case something was stolen from this contract
            if (totalDebt > totalAssets) {
                if (!noLoss) {
                    loss = totalDebt - totalAssets;
                    if (loss > _amountNeeded) loss = _amountNeeded;
                }
            }
            if (!noLoss) {
                liquidatedAmount = _amountNeeded - loss;
            } else {
                if (_amountNeeded > totalAssets) {
                    liquidatedAmount = totalAssets;
                } else {
                    liquidatedAmount = _amountNeeded;
                }
            }
        }
    }

    function harvestTrigger() public view override returns (bool) {
        (bool active, uint256 totalDebt, uint256 lastReport) = vault
            .getStrategyData();

        // Should not trigger if Strategy is not activated
        if (active) return false;

        // Should not trigger if we haven't waited long enough since previous harvest
        if (block.timestamp - lastReport < minReportDelay) return false;

        // Should trigger if hasn't been called in a while
        if (block.timestamp - lastReport >= maxReportDelay) return true;

        // If some amount is owed, pay it back
        // NOTE: Since debt is based on deposits, it makes sense to guard against large
        //       changes to the value from triggering a harvest directly through user
        //       behavior. This should ensure reasonable resistance to manipulation
        //       from user-initiated withdrawals as the outstanding debt fluctuates.
        (uint256 outstanding, ) = vault.excessDebt(address(this));
        if (outstanding > debtThreshold) return true;

        // Check for profits and losses
        uint256 total = _estimatedTotalAssets();
        // Trigger if we have a loss to report
        if (total + debtThreshold < totalDebt) return true;

        uint256 profit = 0;
        if (total > totalDebt) profit = total - totalDebt; // We've earned a profit!

        // Otherwise, only trigger if it "makes sense" economically (gas cost
        // is <N% of value moved)
        uint256 credit = vault.creditAvailable();
        return (0 < credit + profit);
    }

    function harvest() external override {
        uint256 profit = 0;
        uint256 loss = 0;
        (uint256 excessDebt, ) = vault.excessDebt(address(this));
        uint256 debtPayment = 0;
        if (emergencyExit) {
            // Free up as much capital as possible
            uint256 totalAssets = _estimatedTotalAssets();
            // NOTE: use the larger of total assets or debt outstanding to book losses properly
            (debtPayment, loss) = _liquidatePosition(
                totalAssets > excessDebt ? totalAssets : excessDebt
            );
            // NOTE: take up any remainder here as profit
            if (debtPayment > excessDebt) {
                profit = debtPayment - excessDebt;
                debtPayment = excessDebt;
            }
        } else {
            // Free up returns for Vault to pull
            (profit, loss, debtPayment) = _prepareReturn(excessDebt);
        }
        // Allow Vault to take up to the "harvested" balance of this contract,
        // which is the amount it has earned since the last time it reported to
        // the Vault.
        excessDebt = vault.report(profit, loss, debtPayment, false);

        // Check if free returns are left, and re-invest them
        _adjustPosition(excessDebt);

        emit LogHarvested(profit, loss, debtPayment, excessDebt);
    }

    function _estimatedTotalAssets() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function expectedReturn() external view returns (uint256) {
        uint256 estimateAssets = _estimatedTotalAssets();

        uint256 debt = vault.getStrategyDebt();
        if (debt > estimateAssets) {
            return 0;
        } else {
            return estimateAssets - debt;
        }
    }

    function tendTrigger(uint256 callCost) public pure override returns (bool) {
        if (callCost > 0) return false;
        return true;
    }

    function setAmmCheck(bool status) external {
        ammStatus = status;
    }

    function migrate(address newStrategy) external {
        require(msg.sender == address(vault), "migrate: !vault");
        want.transfer(newStrategy, want.balanceOf(address(this)));
    }
}

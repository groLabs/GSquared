// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

interface IOusdVault {
    function redeemAll(uint256 _minimumUnitAmount) external;
}

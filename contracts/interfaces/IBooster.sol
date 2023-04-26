// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

/// Convex booster interface
interface IBooster {
    function poolInfo(uint256)
        external
        view
        returns (
            address,
            address,
            address,
            address,
            address,
            bool
        );

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);
}

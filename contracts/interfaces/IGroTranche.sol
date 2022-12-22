// SPDX-License-Identifier: AGPLv3

pragma solidity 0.8.10;

interface IGroTranche {
    function deposit(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address recipient
    ) external returns (uint256);

    function withdraw(
        uint256 _amount,
        uint256 _index,
        bool _tranche,
        address recipient
    ) external returns (uint256);

    function getTrancheToken(bool _tranche)
        external
        view
        returns (address trancheToken);
}

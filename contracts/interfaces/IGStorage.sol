// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

interface IGStorage {
    function setTrancheBalance(bool _tranche, uint256 _balance) external;

    function getTrancheBalance(bool _tranche) external view returns (uint256);
}

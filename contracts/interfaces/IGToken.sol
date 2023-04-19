// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

interface IGToken {
    function mint(address recipient, uint256 amount) external;

    function burn(address recipient, uint256 amount) external;

    function totalSupplyBase() external view returns (uint256);

    function factor() external view returns (uint256);

    function factor(uint256 amount) external view returns (uint256);

    function trancheBalance() external view returns (uint256);

    function getTokenAssets(uint256 amount) external view returns (uint256);

    function getTokenAmountFromAssets(uint256 assets)
        external
        view
        returns (uint256);

    function balanceOf(address user) external view returns (uint256);
}

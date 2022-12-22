// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "./MockERC20.sol";

contract MockUSDT is MockERC20 {
    constructor() ERC20("USDT", "USDT", 6) {}

    function faucet() external override {
        require(!claimed[msg.sender], "Already claimed");
        claimed[msg.sender] = true;
        _mint(msg.sender, 1E11);
    }
}

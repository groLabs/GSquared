// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./MockStrategy.sol";
import "../interfaces/IGVault.sol";

contract MockConvexStrategyFactory {
    using Clones for address;

    address public immutable implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function createProxyStrategy(address _vault)
        public
        returns (address strategy)
    {
        strategy = implementation.clone();
        MockStrategy(strategy).initialize(_vault);
    }
}

// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./ConvexStrategy.sol";
import "../interfaces/IGVault.sol";

contract ConvexStrategyFactory {
    using Clones for address;

    address public immutable implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function createProxyStrategy(
        IGVault _vault,
        address _owner,
        uint256 _pid,
        address _metaPool
    ) public returns (address strategy) {
        strategy = implementation.clone();
        ConvexStrategy(strategy).initialize(_vault, _owner, _pid, _metaPool);
    }
}

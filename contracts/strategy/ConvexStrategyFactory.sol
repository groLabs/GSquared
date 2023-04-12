// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./ConvexStrategy.sol";
import "../interfaces/IGVault.sol";

contract ConvexStrategyFactory {
    using Clones for address;

    address public immutable implementation;

    /// @notice Factory constructor
    /// @param _implementation Address of the strategy implementation
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /// @notice Strategy initialization
    /// @param _vault Vault that holds the strategy
    /// @param _pid PID of Convex reward pool
    /// @param _metaPool Underlying meta pool
    ///     - used when LP token and Meta pool dont match (older metapools)
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

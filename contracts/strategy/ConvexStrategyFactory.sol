// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ConvexStrategy.sol";
import "../interfaces/IGVault.sol";

contract ConvexStrategyFactory is Ownable {
    using Clones for address;

    address public implementation;

    event LogStrategyImplementationChanged(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    /// @notice Factory constructor
    /// @param _implementation Address of the strategy implementation
    constructor(address _implementation) Ownable() {
        address oldImplementation = implementation;
        implementation = _implementation;
        emit LogStrategyImplementationChanged(
            oldImplementation,
            _implementation
        );
    }

    /// @notice Set implementation address
    /// @param _implementation Address of the strategy implementation
    function setImplementation(address _implementation) public onlyOwner {
        implementation = _implementation;
    }

    /// @notice Get implementation address
    function getImplementation() public view returns (address) {
        return implementation;
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

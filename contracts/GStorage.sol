// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import {Owned} from "./solmate/src/auth/Owned.sol";
import {IGStorage} from "./interfaces/IGStorage.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

/// @title GStorage contract to store token USD balances
/// @notice GTranche contract will call this contract to update the USD balances of the tranches
contract GStorage is IGStorage, Owned {
    /*//////////////////////////////////////////////////////////////
                    STORAGE VARIABLES & TYPES
    //////////////////////////////////////////////////////////////*/
    // Accounting for the total "value" (as defined in the oracle/relation module)
    //  of the tranches: True => Senior Tranche, False => Junior Tranche
    mapping(bool => uint256) public trancheBalances;

    address public gTranche;

    constructor() Owned(msg.sender) {}

    function setGTrancheAddress(address _gtranche) external onlyOwner {
        gTranche = _gtranche;
    }

    /// @notice Require that the caller is the GTranche contract
    /// @notice Use this carefully
    /// TODO: need to check all possible implications of this in terms of security
    function setTrancheBalance(bool _tranche, uint256 _balance) external {
        _requireCallerIsGTranche();
        trancheBalances[_tranche] = _balance;
    }

    /// @notice Increase the USD balance of the tranche
    function increaseTrancheBalance(bool _tranche, uint256 _balance) external {
        _requireCallerIsGTranche();
        trancheBalances[_tranche] += _balance;
    }

    /// @notice Decrease the USD balance of the tranche
    function decreaseTrancheBalance(bool _tranche, uint256 _balance) external {
        _requireCallerIsGTranche();
        trancheBalances[_tranche] -= _balance;
    }

    /// @notice Returns the USD balance of the tranche
    function getTrancheBalance(bool _tranche) external view returns (uint256) {
        return trancheBalances[_tranche];
    }

    /// @notice Require that the caller is the GTranche contract
    function _requireCallerIsGTranche() internal view {
        require(msg.sender == address(gTranche), "Caller is not GTranche");
    }
}

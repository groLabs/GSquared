// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import {Owned} from "./solmate/src/auth/Owned.sol";
import {console2} from "../lib/forge-std/src/console2.sol";

//  ________  ________  ________
//  |\   ____\|\   __  \|\   __  \
//  \ \  \___|\ \  \|\  \ \  \|\  \
//   \ \  \  __\ \   _  _\ \  \\\  \
//    \ \  \|\  \ \  \\  \\ \  \\\  \
//     \ \_______\ \__\\ _\\ \_______\
//      \|_______|\|__|\|__|\|_______|

/// @title GStorage contract to store token USD balances
contract GStorage is Owned {
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

    function setTrancheBalance(bool _tranche, uint256 _balance) external {
        console2.log("msg sender", msg.sender);
        _requireCallerIsGTranche();
        trancheBalances[_tranche] = _balance;
    }

    function increaseTrancheBalance(bool _tranche, uint256 _balance) external {
        _requireCallerIsGTranche();
        trancheBalances[_tranche] += _balance;
    }

    function decreaseTrancheBalance(bool _tranche, uint256 _balance) external {
        _requireCallerIsGTranche();
        trancheBalances[_tranche] -= _balance;
    }

    function getTrancheBalance(bool _tranche) external view returns (uint256) {
        return trancheBalances[_tranche];
    }

    function _requireCallerIsGTranche() internal view {
        require(msg.sender == address(gTranche), "Caller is not GTranche");
    }
}

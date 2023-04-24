// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import {Owned} from "../solmate/src/auth/Owned.sol";
import {Errors} from "./Errors.sol";

contract Whitelist is Owned {
    mapping(address => bool) public whitelist;

    event LogAddToWhitelist(address indexed user);
    event LogRemoveFromWhitelist(address indexed user);

    constructor() Owned(msg.sender) {}

    modifier onlyWhitelist() {
        if (!whitelist[msg.sender]) {
            revert Errors.NotInWhitelist();
        }
        _;
    }

    function addToWhitelist(address user) external onlyOwner {
        if (user == address(0)) {
            revert Errors.ZeroAddress();
        }
        whitelist[user] = true;
        emit LogAddToWhitelist(user);
    }

    function removeFromWhitelist(address user) external onlyOwner {
        if (user == address(0)) {
            revert Errors.ZeroAddress();
        }
        whitelist[user] = false;
        emit LogRemoveFromWhitelist(user);
    }
}

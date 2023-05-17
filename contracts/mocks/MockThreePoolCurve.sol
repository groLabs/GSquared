// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "../interfaces/ICurve3Pool.sol";

contract MockThreePoolCurve is ICurve3Pool {
    mapping(address => uint256) public balances;

    function get_virtual_price() external pure override returns (uint256) {
        return 1e18;
    }

    function add_liquidity(
        uint256[3] calldata _deposit_amounts,
        uint256 _min_mint_amount
    ) external {
        for (uint256 i = 0; i < _deposit_amounts.length; i++) {
            balances[msg.sender] += _deposit_amounts[i];
        }
    }

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external {
        balances[msg.sender] -= _token_amount;
    }
}

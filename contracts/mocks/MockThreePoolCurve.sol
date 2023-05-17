// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

import "../interfaces/ICurve3Pool.sol";
import "./Mock3CRV.sol";

contract MockThreePoolCurve is ICurve3Pool {
    Mock3CRV public threeCrv;

    function setThreeCrv(address _threeCrv) external {
        threeCrv = Mock3CRV(_threeCrv);
    }

    function get_virtual_price() external pure override returns (uint256) {
        return 1e18;
    }

    function add_liquidity(
        uint256[3] calldata _deposit_amounts,
        uint256 _min_mint_amount
    ) external {
        uint256 balances;
        for (uint256 i = 0; i < _deposit_amounts.length; i++) {
            balances += _deposit_amounts[i];
        }
        threeCrv.mint(msg.sender, balances);
    }

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external {
        threeCrv.burn(msg.sender, _token_amount);
    }
}

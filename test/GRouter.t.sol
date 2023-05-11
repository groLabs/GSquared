// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Base.GSquared.t.sol";

contract RouterTest is Test, BaseSetup {
    using stdStorage for StdStorage;

    function testDepositWithdrawMulti() public {
        vm.startPrank(alice);

        setStorage(alice, DAI.balanceOf.selector, address(DAI), 100E20);
        gTranche.setApprovalForAll(address(gRouter), true);
        uint256 aliceDaiBalance = DAI.balanceOf(alice);

        DAI.approve(address(gRouter), MAX_UINT);

        gRouter.deposit(100E18, 0, false, 0);

        assertLt(DAI.balanceOf(alice), aliceDaiBalance);
        assertGt(gTranche.balanceOfWithFactor(alice, 0), 0);

        aliceDaiBalance = DAI.balanceOf(alice);
        gRouter.deposit(50E18, 0, true, 0);

        assertLt(DAI.balanceOf(alice), aliceDaiBalance);
        assertGt(gTranche.balanceOfWithFactor(alice, 1), 0);

        aliceDaiBalance = DAI.balanceOf(alice);
        uint256 alicePWRDBalance = gTranche.balanceOfWithFactor(alice, 1);
        gRouter.withdraw(10E18, 0, true, 0);

        assertGt(DAI.balanceOf(alice), aliceDaiBalance);
        assertLt(gTranche.balanceOfWithFactor(alice, 1), alicePWRDBalance);

        aliceDaiBalance = DAI.balanceOf(alice);
        uint256 aliceGVTBalance = gTranche.balanceOfWithFactor(alice, 0);
        gRouter.withdraw(10E16, 0, false, 0);

        assertGt(DAI.balanceOf(alice), aliceDaiBalance);
        assertLt(gTranche.balanceOfWithFactor(alice, 0), aliceGVTBalance);

        vm.stopPrank();
    }

    function testDepositWithdrawLegacy() public {
        vm.startPrank(alice);
        gTranche.setApprovalForAll(address(gRouter), true);
        setStorage(alice, DAI.balanceOf.selector, address(DAI), 100E20);

        uint256 aliceDaiBalance = DAI.balanceOf(alice);

        DAI.approve(address(gRouter), MAX_UINT);

        gRouter.depositGvt([uint256(100E18), 0, 0], 0, ZERO);

        assertLt(DAI.balanceOf(alice), aliceDaiBalance);
        assertGt(gTranche.balanceOfWithFactor(alice, 0), 0);

        aliceDaiBalance = DAI.balanceOf(alice);
        gRouter.depositPwrd([uint256(50E18), 0, 0], 0, ZERO);

        assertLt(DAI.balanceOf(alice), aliceDaiBalance);
        assertGt(gTranche.balanceOfWithFactor(alice, 1), 0);

        aliceDaiBalance = DAI.balanceOf(alice);
        uint256 alicePWRDBalance = gTranche.balanceOfWithFactor(alice, 1);
        gRouter.withdrawByStablecoin(true, 0, alicePWRDBalance, 0);

        assertGt(DAI.balanceOf(alice), aliceDaiBalance);
        assertLt(gTranche.balanceOfWithFactor(alice, 1), alicePWRDBalance);

        aliceDaiBalance = DAI.balanceOf(alice);
        uint256 aliceGVTBalance = gTranche.balanceOfWithFactor(alice, 0);
        gRouter.withdrawByStablecoin(false, 0, aliceGVTBalance, 0);

        assertGt(DAI.balanceOf(alice), aliceDaiBalance);
        assertLt(gTranche.balanceOfWithFactor(alice, 0), aliceGVTBalance);

        vm.stopPrank();
    }

    /// @dev Test depositing with zero amount should revert
    function testDepositZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AmountIsZero.selector));
        gRouter.deposit(0, 0, true, 123e18);
    }
}

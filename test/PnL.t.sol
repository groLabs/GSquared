// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Base.GSquared.t.sol";
import "../contracts/utils/StrategyQueue.sol";
import "../contracts/pnl/PnL.sol";

contract PnLTest is Test, BaseSetup {
    using stdStorage for StdStorage;
    uint256 public constant YEAR_IN_SECONDS = 31556952;

    PnL private profitAndLoss;

    function setUp() public virtual override {
        BaseSetup.setUp();
        vm.startPrank(BASED_ADDRESS);
        profitAndLoss = new PnL(address(gTranche));
        gTranche.setPnL(profitAndLoss);
        vm.stopPrank();
    }

    function testCanDepositBelowUtilisation(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E18);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        vm.startPrank(alice);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        vm.stopPrank();
        assertLe(gTranche.trancheBalances(1), gTranche.trancheBalances(0));
    }

    function testCannotDepositAboveUtilisation(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E18);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior < shares / 3) depositSenior = shares / 3;
        if (depositSenior > (shares - shares / 4))
            depositSenior = shares - shares / 4;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 4, 0, false, alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.UtilisationTooHigh.selector)
        );
        gTranche.deposit(depositSenior, 0, true, alice);
        vm.stopPrank();
    }

    function testCanWithdrawBelowUtilisation(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E18);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = ((shares / 2 - depositSenior) *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw == 0) withdraw = 1;

        gTranche.withdraw(withdraw, 0, false, alice);
        vm.stopPrank();
    }

    function testCannotWithdrawBelowUtilisation(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = ((shares / 2 - depositSenior + depositSenior / 10) *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw == 0) withdraw = 1E16;
        if (withdraw > gTranche.balanceOfWithFactor(alice, 0))
            withdraw = gTranche.balanceOfWithFactor(alice, 0);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.UtilisationTooHigh.selector)
        );
        gTranche.withdraw(withdraw, 0, false, alice);
        vm.stopPrank();
    }

    function testSeniorAssetsDecreaseOnWithdrawal(
        uint128 _amount,
        uint128 _depositSenior,
        uint256 _withdrawSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        vm.assume(_withdrawSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = uint256(_withdrawSenior);
        uint256 seniorAmount = (depositSenior *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw > seniorAmount) {
            withdraw = seniorAmount;
        }

        uint256 seniorAssets = gTranche.trancheBalances(1);
        gTranche.withdraw(withdraw, 0, true, alice);
        vm.stopPrank();
        assertLt(gTranche.trancheBalances(1), seniorAssets);
    }

    function testSeniorAssetsIncreaseOnDeposit(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        uint256 seniorAssets = gTranche.trancheBalances(1);
        gTranche.deposit(depositSenior, 0, true, alice);

        vm.stopPrank();
        assertGt(gTranche.trancheBalances(1), seniorAssets);
    }

    function testJuniorAssetsDecreaseOnWithdrawal(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = ((shares / 2 - depositSenior) *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw == 0) withdraw = 1;

        uint256 juniorAssets = gTranche.trancheBalances(0);
        gTranche.withdraw(withdraw, 0, false, alice);
        assertLt(gTranche.trancheBalances(0), juniorAssets);
        vm.stopPrank();
    }

    function testJuniorAssetsIncreaseOnDeposit(uint128 _amount) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        uint256 amount = uint256(_amount);
        uint256 shares = depositIntoVault(address(alice), amount);

        vm.startPrank(alice);
        uint256 juniorAssets = gTranche.trancheBalances(0);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);

        vm.stopPrank();
        assertGt(gTranche.trancheBalances(0), juniorAssets);
    }

    function testUtilisationIncreasesOnMintingOfSeniorTrancheToken(
        uint128 _amount,
        uint256 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E24);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        uint256 initialUtlization = gTranche.utilisation();
        gTranche.deposit(depositSenior, 0, true, alice);

        vm.stopPrank();
        assertGt(gTranche.utilisation(), initialUtlization);
    }

    function testUtilisationDecreasesOnBurningOfSeniorTrancheToken(
        uint128 _amount,
        uint128 _depositSenior,
        uint256 _withdrawSenior
    ) public {
        if (_amount > 1E26) _amount = 1E26;
        if (_amount < 1E21) _amount = 1E21;
        vm.assume(_depositSenior > 1E24);
        vm.assume(_withdrawSenior > 1E25);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = uint256(_withdrawSenior);
        uint256 seniorAmount = (depositSenior *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(1);
        if (withdraw > seniorAmount) {
            withdraw = seniorAmount;
        }

        uint256 initialUtlization = gTranche.utilisation();
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.withdraw(withdraw, 0, true, alice);
        vm.stopPrank();
        assertLt(gTranche.utilisation(), initialUtlization);
    }

    function testUtilisationDecreasesOnMintingOfJuniorTrancheToken(
        uint256 _amount
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        uint256 amount = uint256(_amount);
        uint256 shares = depositIntoVault(address(alice), amount);

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(shares / 4, 0, true, alice);

        uint256 initialUtlization = gTranche.utilisation();
        gTranche.deposit(shares / 5, 0, false, alice);
        vm.stopPrank();
        assertLt(gTranche.utilisation(), initialUtlization);
    }

    function testUtilisationIncreasesOnBurningOfJuniorTrancheToken(
        uint128 _amount,
        uint128 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        uint256 withdraw = ((shares / 2 - depositSenior) *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw == 0) withdraw = 1;

        uint256 initialUtlization = gTranche.utilisation();
        gTranche.withdraw(withdraw, 0, false, alice);
        assertGe(gTranche.utilisation(), initialUtlization);
        vm.stopPrank();
    }

    function testProfitDistributionCurve(
        uint256 _amount,
        uint256 _depositSenior
    ) public {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);
        vm.stopPrank();
        (uint256[2] memory initialAssets, , ) = gTranche.pnlDistribution();

        setStorage(
            address(strategy),
            THREE_POOL_TOKEN.balanceOf.selector,
            address(THREE_POOL_TOKEN),
            amount * 6
        );
        vm.startPrank(BASED_ADDRESS);
        strategy.runHarvest();
        vm.stopPrank();

        vm.warp(block.timestamp + 10000);
        (uint256[2] memory finalAssets, , ) = gTranche.pnlDistribution();
        assertGt(finalAssets[0], initialAssets[0]);
        assertGt(finalAssets[1], initialAssets[1]);
    }

    function testSeniorTrancheShouldGetFixedRateReturn(
        uint128 _amount,
        uint128 _depositSenior
    ) private {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 2) depositSenior = shares / 2;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);
        vm.stopPrank();
        (uint256[2] memory initialAssets, , ) = gTranche.pnlDistribution();

        vm.warp(block.timestamp + YEAR_IN_SECONDS);
        (uint256[2] memory finalAssets, , ) = gTranche.pnlDistribution();
        assertApproxEqAbs(
            (finalAssets[1] * 10000) / initialAssets[1],
            10200,
            1
        );
        assertEq(
            initialAssets[0] - (finalAssets[1] - initialAssets[1]),
            finalAssets[0]
        );
    }

    function testSeniorTrancheShouldGetFixedRateReturnChangesJuniorDepth(
        uint128 _amount,
        uint128 _depositSenior
    ) private {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 4) depositSenior = shares / 4;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2 + 1, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        (uint256[2] memory initialAssets, , ) = gTranche.pnlDistribution();

        vm.warp(block.timestamp + YEAR_IN_SECONDS / 2);

        (uint256[2] memory preWithdrawalAssets, , ) = gTranche
            .pnlDistribution();
        uint256 withdraw = ((shares / 4 - depositSenior) *
            ICurve3Pool(THREE_POOL).get_virtual_price()) /
            gTranche.getPricePerShare(0);
        if (withdraw == 0) withdraw = 1;
        (, uint256 withdrawnAssetValue) = gTranche.withdraw(
            withdraw,
            0,
            false,
            alice
        );

        (uint256[2] memory postWithdrawalAssets, , ) = gTranche
            .pnlDistribution();

        vm.warp(block.timestamp + YEAR_IN_SECONDS / 2);

        vm.stopPrank();
        (uint256[2] memory finalAssets, , ) = gTranche.pnlDistribution();
        assertApproxEqAbs(
            (finalAssets[1] * 10000) /
                postWithdrawalAssets[1] +
                (preWithdrawalAssets[1] * 10000) /
                initialAssets[1],
            10100 * 2,
            1 * 2
        );
        assertApproxEqAbs(
            initialAssets[0] -
                (finalAssets[1] - initialAssets[1]) -
                withdrawnAssetValue,
            finalAssets[0],
            1E6
        );
    }

    function testSeniorTrancheShouldGetFixedRateReturnChangesInSeniorDepth(
        uint128 _amount,
        uint128 _depositSenior
    ) private {
        vm.assume(_amount < 1E26);
        vm.assume(_amount > 1E20);
        vm.assume(_depositSenior > 1E20);
        uint256 amount = uint256(_amount);
        uint256 depositSenior = uint256(_depositSenior);
        uint256 shares = depositIntoVault(address(alice), amount);
        if (depositSenior > shares / 4) depositSenior = shares / 4;

        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(shares / 2 + 1, 0, false, alice);
        gTranche.deposit(depositSenior, 0, true, alice);

        (uint256[2] memory initialAssets, , ) = gTranche.pnlDistribution();

        vm.warp(block.timestamp + YEAR_IN_SECONDS / 2);

        (uint256[2] memory preWithdrawalAssets, , ) = gTranche
            .pnlDistribution();
        uint256 withdraw = depositSenior / 2;
        if (withdraw == 0) withdraw = 1;
        (, uint256 withdrawnAssetValue) = gTranche.withdraw(
            withdraw,
            0,
            true,
            alice
        );

        (uint256[2] memory postWithdrawalAssets, , ) = gTranche
            .pnlDistribution();

        vm.warp(block.timestamp + YEAR_IN_SECONDS / 2);

        vm.stopPrank();
        (uint256[2] memory finalAssets, , ) = gTranche.pnlDistribution();

        assertApproxEqAbs(
            (finalAssets[1] * 10000) /
                postWithdrawalAssets[1] +
                (preWithdrawalAssets[1] * 10000) /
                initialAssets[1],
            10100 * 2,
            1 * 2
        );
        assertApproxEqAbs(
            initialAssets[0] -
                (finalAssets[1] - (initialAssets[1] - withdrawnAssetValue)),
            finalAssets[0],
            1E6
        );
    }

    function testsShouldBePossibleToResetJuniorDebt() public {
        uint256 amount = 1E22;
        uint256 shares = depositIntoVault(address(alice), amount);
        uint256 seniorDeposit = shares / 2;
        uint256 juniorDeposit = shares / 2;
        vm.startPrank(alice);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        gTranche.deposit(seniorDeposit, 0, false, alice);
        gTranche.deposit(juniorDeposit, 0, true, alice);
        vm.stopPrank();
        uint256 initialAssets = gVault.totalAssets();
        // Incur loss when withdrawing Senior + assets in vault decreased
        setStorage(
            BASED_ADDRESS,
            GVault.totalAssets.selector,
            address(gVault),
            initialAssets / 2
        );
        vm.startPrank(alice);
        gTranche.withdraw(seniorDeposit / 2, 0, true, alice);
        vm.stopPrank();
        // Make sure junior loss appeared
        assertGt(profitAndLoss.juniorLoss(), 0);

        vm.startPrank(BASED_ADDRESS);
        profitAndLoss.resetJuniorDebt();
        vm.stopPrank();
        // Make sure junior loss is 0 after reset
        assertEq(profitAndLoss.juniorLoss(), 0);
    }
}

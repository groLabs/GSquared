// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Base.GSquared.t.sol";

contract TrancheTest is Test, BaseSetup {
    using stdStorage for StdStorage;
    address frax_lp = address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address frax = address(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    address fraxConvexPool =
        address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address fraxConvexRewards =
        address(0xB900EF131301B307dB5eFcbed9DBb50A3e209B2e);
    uint256 frax_lp_pid = 32;

    ConvexStrategy convexStrategy;

    function setUp() public virtual override {
        BaseSetup.setUp();
        vm.startPrank(BASED_ADDRESS);
        setupConvexStrategy();
        setStorage(BASED_ADDRESS, DAI.balanceOf.selector, address(DAI), 200E18);
        DAI.approve(address(gRouter), MAX_UINT);
        gRouter.deposit(100E18, 0, false, 0);
        gRouter.deposit(100E18, 0, true, 0);
        vm.stopPrank();
    }

    function setupConvexStrategy() public {
        convexStrategy = new ConvexStrategy(
            IGVault(address(gVault)),
            BASED_ADDRESS,
            frax_lp_pid,
            frax_lp
        );
        StopLossLogic snl = new StopLossLogic();

        convexStrategy.setStopLossLogic(address(snl));
        convexStrategy.setHarvestThresholds(1, 1);
        snl.setStrategy(address(convexStrategy), 1e18, 400);
        convexStrategy.setKeeper(BASED_ADDRESS);
        gVault.removeStrategy(address(strategy));
        gVault.addStrategy(address(convexStrategy), 9000);
    }

    function testDepositSimple() public {
        vm.startPrank(alice);
        setStorage(alice, DAI.balanceOf.selector, address(DAI), 100E20);

        DAI.approve(address(gRouter), MAX_UINT);
        uint256 initialSenior = gTranche.trancheBalances(true);
        uint256 initialJunior = gTranche.trancheBalances(false);

        gRouter.deposit(100E18, 0, false, 0);
        gRouter.deposit(50E18, 0, true, 0);

        uint256 finalSenior = gTranche.trancheBalances(true);
        uint256 finalJunior = gTranche.trancheBalances(false);
        assertApproxEqRel(initialJunior + 100E18, finalJunior, 1E15);
        assertApproxEqRel(initialSenior + 50E18, finalSenior, 1E15);

        gRouter.deposit(100E18, 0, false, 0);
        gRouter.deposit(50E18, 0, true, 0);
        vm.stopPrank();
    }

    function testWithdrawalSimple() public {
        vm.startPrank(alice);
        setStorage(alice, DAI.balanceOf.selector, address(DAI), 15000E20);

        DAI.approve(address(gRouter), MAX_UINT);

        gRouter.deposit(10000E18, 0, false, 0);
        gRouter.deposit(5000E18, 0, true, 0);
        vm.stopPrank();

        vm.startPrank(BASED_ADDRESS);
        //convexStrategy.runHarvest();
        vm.stopPrank();

        vm.startPrank(alice);
        GVT.approve(address(gRouter), MAX_UINT);
        PWRD.approve(address(gRouter), MAX_UINT);

        uint256 initialSenior = gTranche.trancheBalances(true);
        uint256 initialJunior = gTranche.trancheBalances(false);

        uint256 withdrawJunior = (100E18 * 1E18) / GVT.getPricePerShare();

        gRouter.withdraw(4000E18, 0, true, 0);
        gRouter.withdraw(withdrawJunior, 0, false, 0);

        uint256 finalSenior = gTranche.trancheBalances(true);
        uint256 finalJunior = gTranche.trancheBalances(false);
        // assertApproxEqRel(initialJunior - 40E18, finalJunior, 1E16);
        // assertApproxEqRel(initialSenior - 20E18, finalSenior, 1E16);

        vm.stopPrank();
    }

    /// Given a user with assets in the Senior tranche
    /// When there is a loss
    /// Then the user should not experience any loss on
    /// Their senior tranche assets, unless the junior tranche
    ///  is depleated
    ///  invariant:
    ///  ∀ S, J ∃ T, if S₁ >= S₀, then J₁ = 0
    ///  for all gain/losses in senior and junior tranche in the set of tranche asset changes,
    ///  the senior tranche can only be be reduced if and only if the junior tranche is 0
    function testSeniorTrancheLosses(
        uint256 _deposit,
        uint16 _change,
        uint256 _i,
        bool _loss
    ) public {
        uint256 deposit = bound(_deposit, 1E22, 1E26);
        uint256 change = bound(_change, 100, 10000);
        uint256 i = bound(_i, 2, 4);

        for (uint256 j; j < i; j++) {
            address user = users[j];
            prepUser(user);
            vm.startPrank(user);
            gRouter.deposit(deposit, 0, false, 0);
            gRouter.deposit(deposit, 0, true, 0);
            vm.stopPrank();
        }

        vm.startPrank(BASED_ADDRESS);
        convexStrategy.runHarvest();

        uint256 utilisation = gTranche.utilisation();
        uint256 BP = change % 10000;
        uint256 assets = gVault.totalAssets();
        uint256 initialSeniorTrancheAssets = gTranche.trancheBalances(true);

        if (_loss) {
            uint256 loss = assets - (assets * change) / 10000;
            //setStorage(address(convexStrategy), ERC20(fraxConvexRewards).balanceOf.selector, fraxConvexRewards, loss);
        } else {
            uint256 gain = assets + (assets * change) / 10000;
            //setStorage(address(convexStrategy), ERC20(fraxConvexRewards).balanceOf.selector, fraxConvexRewards, gain);
        }

        convexStrategy.runHarvest();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 aliceSeniorAssets = PWRD.balanceOf(alice);
        uint256 aliceJuniorAssets = GVT.balanceOf(alice);
        gRouter.withdraw(aliceSeniorAssets / 10, 0, true, 0);
        initialSeniorTrancheAssets =
            initialSeniorTrancheAssets -
            aliceSeniorAssets /
            10;
        vm.stopPrank();

        // if (_loss) {
        //     if (change <= 5000) {
        //         assertGe(gTranche.trancheBalances(true), initialSeniorTrancheAssets);
        //     } else {
        //         assertLe(gTranche.trancheBalances(true), initialSeniorTrancheAssets);
        //     }
        // } else {
        //     assertGe(gTranche.trancheBalances(true), initialSeniorTrancheAssets);
        // }
    }

    /// Given a user with assets in the Junior tranche
    /// When there is a gain
    /// Then all the gains should go to the Junior tranche
    ///  invariant:
    ///  ∀ S, J ∃ T, if S₁ >= S₀, then J₁ = 0
    ///  for all gain/losses in senior and junior tranche in the set of tranche asset changes,
    ///  the senior tranche can only be be reduced if and only if the junior tranche is 0
    function testJuniorGetsAllYield(
        uint256 deposit,
        uint16 _change,
        uint256 i
    ) public {
        uint256 change = uint256(_change) % 10000;
        vm.assume(deposit > 1E20);
        vm.assume(deposit < 1E25);
        vm.assume(change > 100);
        vm.assume(change <= 10000);
        vm.assume(i > 1);

        vm.startPrank(BASED_ADDRESS);
        pnl.setRate(0);
        vm.stopPrank();

        for (uint256 j; j < (i % 4) + 1; j++) {
            address user = users[j];
            prepUser(user);
            vm.startPrank(user);
            gRouter.deposit(deposit, 0, false, 0);
            gRouter.deposit(deposit, 0, true, 0);
            vm.stopPrank();
        }

        vm.startPrank(BASED_ADDRESS);
        convexStrategy.runHarvest();
        vm.stopPrank();

        uint256 utilisation = gTranche.utilisation();
        uint256 BP = change % 10000;
        uint256 assets = gVault.totalAssets();
        uint256 initialSeniorTrancheAssets = gTranche.trancheBalances(true);
        uint256 initialJuniorTrancheAssets = gTranche.trancheBalances(false);

        vm.startPrank(BASED_ADDRESS);
        uint256 gain = assets + (assets * change) / BP;
        setStorage(
            address(convexStrategy),
            THREE_POOL_TOKEN.balanceOf.selector,
            address(THREE_POOL_TOKEN),
            gain
        );

        convexStrategy.runHarvest();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 aliceSeniorAssets = PWRD.balanceOf(alice);
        uint256 aliceJuniorAssets = GVT.balanceOf(alice);
        gRouter.withdraw(aliceSeniorAssets / 10, 0, true, 0);
        initialSeniorTrancheAssets =
            initialSeniorTrancheAssets -
            aliceSeniorAssets /
            10;
        initialJuniorTrancheAssets =
            initialJuniorTrancheAssets -
            aliceJuniorAssets /
            10;
        vm.stopPrank();

        assertEq(gTranche.trancheBalances(true), initialSeniorTrancheAssets);
        assertGt(gTranche.trancheBalances(false), initialJuniorTrancheAssets);
    }

    function testwithdrawNoImpact(
        uint256 deposit,
        uint8 _i,
        uint8 _k
    ) public {
        uint256 i = uint256((_i % 4) + 1);
        uint256 k = uint256((_k % 25) + 1);
        vm.assume(deposit > 1E20);
        vm.assume(deposit < 1E25);
        vm.assume(i > 1);
        vm.assume(k > 1);

        vm.startPrank(BASED_ADDRESS);
        pnl.setRate(0);
        vm.stopPrank();

        runDeposit(users, deposit, i, k);

        uint256 seniorTotal = gTranche.trancheBalances(true);
        uint256 juniorTotal = gTranche.trancheBalances(false);
        uint256 totalWithdrawnSenior;
        uint256 totalWithdrawnJunior;

        for (uint256 j; j < i; j++) {
            (uint256 withdrawnSenior, uint256 withdrawnJunior) = runWithdrawal(
                users[j],
                k
            );
            totalWithdrawnSenior += withdrawnSenior;
            totalWithdrawnJunior += withdrawnJunior;
        }

        assertApproxEqAbs(
            gTranche.trancheBalances(true),
            delta(seniorTotal, totalWithdrawnSenior),
            1E6
        );
        assertApproxEqAbs(
            gTranche.trancheBalances(false),
            delta(juniorTotal, totalWithdrawnJunior),
            1E6
        );
    }

    function runDeposit(
        address payable[] memory _users,
        uint256 deposit,
        uint256 i,
        uint256 k
    ) public {
        bool _break;
        for (uint256 j; j < i; j++) {
            address user = _users[j];
            prepUserCrv(user);
            vm.startPrank(user);
            _break = false;
            for (uint256 l; l < k; l++) {
                if (deposit > DAI.balanceOf(user)) {
                    ICurve3Pool(THREE_POOL).add_liquidity(
                        [DAI.balanceOf(user), 0, 0],
                        0
                    );
                } else {
                    ICurve3Pool(THREE_POOL).add_liquidity([deposit, 0, 0], 0);
                }
                uint256 balance = THREE_POOL_TOKEN.balanceOf(address(user));
                uint256 shares = gVault.deposit(balance, address(user));

                gTranche.deposit(shares / 2, 0, false, address(user));
                gTranche.deposit(shares / 2, 0, true, address(user));
                if (_break) break;
            }
            vm.stopPrank();
        }
    }

    function _withdraw(
        bool tranche,
        uint256 amount,
        address user
    ) public returns (uint256 withdrawAmount) {
        (, withdrawAmount) = gTranche.withdraw(amount, 0, tranche, user);
    }

    function userWithdrawCheck(
        address user,
        uint256 userSeniorAssets,
        uint256 userJuniorAssets,
        uint256 k
    )
        public
        returns (uint256 seniorAmountWithdrawn, uint256 juniorAmountWithdrawn)
    {
        uint256 SeniorTrancheAssets;
        uint256 JuniorTrancheAssets;

        for (uint256 l; l < k; l++) {
            JuniorTrancheAssets = gTranche.trancheBalances(false);
            vm.startPrank(user);
            if (l + 1 == k) {
                seniorAmountWithdrawn += _withdraw(
                    true,
                    PWRD.balanceOf(user),
                    address(user)
                );
            } else {
                seniorAmountWithdrawn += _withdraw(
                    true,
                    userSeniorAssets / k,
                    address(user)
                );
            }
            assertApproxEqAbs(
                gTranche.trancheBalances(false),
                JuniorTrancheAssets,
                1E6
            );

            SeniorTrancheAssets = gTranche.trancheBalances(true);
            if (l + 1 == k) {
                juniorAmountWithdrawn += _withdraw(
                    false,
                    GVT.balanceOf(user),
                    address(user)
                );
            } else {
                juniorAmountWithdrawn += _withdraw(
                    false,
                    userJuniorAssets / k,
                    address(user)
                );
            }
            vm.stopPrank();
            assertApproxEqAbs(
                gTranche.trancheBalances(true),
                SeniorTrancheAssets,
                1E6
            );
        }
    }

    function runWithdrawal(address user, uint256 k)
        public
        returns (uint256 withdrawnSenior, uint256 withdrawnJunior)
    {
        uint256 userSeniorAssets = PWRD.balanceOf(user);
        uint256 userJuniorAssets = GVT.balanceOf(user);

        uint256 initialSeniorTrancheAssets = gTranche.trancheBalances(true);
        uint256 initialJuniorTrancheAssets = gTranche.trancheBalances(false);

        (withdrawnSenior, withdrawnJunior) = userWithdrawCheck(
            user,
            userSeniorAssets,
            userJuniorAssets,
            k
        );

        assertApproxEqAbs(
            gTranche.trancheBalances(false),
            delta(initialJuniorTrancheAssets, withdrawnJunior),
            1E6
        );
        assertApproxEqAbs(
            gTranche.trancheBalances(true),
            delta(initialSeniorTrancheAssets, withdrawnSenior),
            1E6
        );
    }
}

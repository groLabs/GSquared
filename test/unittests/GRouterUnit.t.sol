// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../BaseUnit.GSquared.t.sol";


contract RouterUnitTest is BaseUnitFixture {
    function setUp() public virtual override {
        BaseUnitFixture.setUp();
    }

    function testDepositUnitSimple(uint256 seniorDeposit, uint256 juniorDeposit) public {
        vm.assume(seniorDeposit > 5e19 && seniorDeposit < 1e30);
        vm.assume(juniorDeposit > seniorDeposit);
        vm.startPrank(alice);
        uint256 juniorDeposit = 100e18;
        uint256 seniorDeposit = 50e18;

        uint256 juniorFactor = gTranche.factor(0);
        // Make sure tranches are empty before Alice deposit
        assertEq(gTranche.trancheBalances(1), 0);
        assertEq(gTranche.trancheBalances(0), 0);
        // Deal some DAI to alice
        dai.faucet();
        dai.approve(address(gRouter), type(uint256).max);
        gRouter.deposit(juniorDeposit, 0, false, 0);
        gRouter.deposit(seniorDeposit, 0, true, 0);
        vm.stopPrank();
        // Check that tranche USD balances are updated
        assertEq(gTranche.trancheBalances(1), seniorDeposit);
        assertEq(gTranche.trancheBalances(0), juniorDeposit);
        // Senior tranche is mapped 1:1
        assertEq(gTranche.balanceOfWithFactor(alice, 1), seniorDeposit);
        // Junior balance of Alice is calculated as jun deposit multiplied by base junior factor
        assertEq(gTranche.balanceOfWithFactor(alice, 0), juniorDeposit * juniorFactor / 1e18);
    }

    function testWithdrawalUnitSimple(uint256 seniorDeposit, uint256 juniorDeposit) public {
        vm.assume(seniorDeposit > 5e19 && seniorDeposit < 1e30);
        vm.assume(juniorDeposit > seniorDeposit);
        vm.startPrank(alice);
        // Allow Router to use Alice's GERC1155 tokens
        gTranche.setApprovalForAll(address(gRouter), true);
        uint256 juniorDeposit = 100e18;
        uint256 seniorDeposit = 50e18;

        uint256 juniorFactor = gTranche.factor(0);
        // Make sure tranches are empty before Alice deposit
        assertEq(gTranche.trancheBalances(1), 0);
        assertEq(gTranche.trancheBalances(0), 0);
        // Deal some DAI to alice
        dai.faucet();
        dai.approve(address(gRouter), type(uint256).max);
        gRouter.deposit(juniorDeposit, 0, false, 0);
        gRouter.deposit(seniorDeposit, 0, true, 0);

        assertEq(gTranche.trancheBalances(1), seniorDeposit);
        // Withdraw half of senior deposit
        gRouter.withdraw(seniorDeposit / 2, 0, true, 0);
        vm.stopPrank();

        // Check Alice balance
        assertEq(gTranche.balanceOfWithFactor(alice, 1), seniorDeposit / 2);
        // Check that tranche USD balances are updated
        assertEq(gTranche.trancheBalances(1), seniorDeposit / 2);
    }
}
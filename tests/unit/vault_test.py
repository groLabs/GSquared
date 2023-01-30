import brownie
import pytest
from brownie import ZERO_ADDRESS, GVault, MockUSDC, MockStrategy, chain
from conftest import *

# DEPOSIT/MINT TESTS

# strategy param index
ACTIVE = 0
DEBT_RATIO = 1
LAST_REPORT = 2
TOTAL_DEBT = 3
TOTAL_GAIN = 4
TOTAL_LOSS = 5


@pytest.fixture(scope="function", autouse=True)
def approve(mock_gro_vault_usdc, mock_usdc, admin, alice, bob):
    for account in [admin, alice, bob]:
        mock_usdc.approve(mock_gro_vault_usdc, MAX_UINT256, {"from": account})


# check user can deposit funds into vault
def test_alice_can_deposit(mock_gro_vault_usdc, alice, mock_usdc):
    print(mock_usdc.balanceOf(alice))
    print(mock_usdc.allowance(alice, mock_gro_vault_usdc))
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.balanceOf(alice) == 1000 * 1e6


# check shares are calculated correctly when multiple users deposit
def test_multiple_deposits(mock_gro_vault_usdc, alice, bob):
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.balanceOf(alice) == 1000 * 1e6
    mock_gro_vault_usdc.deposit(10_000 * 1e6, bob, {"from": bob})
    assert mock_gro_vault_usdc.balanceOf(bob) == 10_000 * 1e6


# Ensure user cannot deposit 0 assets into the vault
def test_no_zero_deposits(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("MinDeposit()")):
        mock_gro_vault_usdc.deposit(0, alice, {"from": alice})


# Ensure user cannot deposit over the deposit limit
@pytest.mark.skip(reason="Removed")
def test_deposit_limit_deposit(mock_gro_vault_usdc, alice, admin):
    mock_gro_vault_usdc.setDepositLimit(1e6, {"from": admin})
    with brownie.reverts(error_string("OverDepositLimit()")):
        mock_gro_vault_usdc.deposit(100 * 1e6, alice, {"from": alice})


# check user can mint shares from vault
def test_alice_can_mint(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.mint(2000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.balanceOf(alice) == 2000 * 1e6


# check shares are calculated correctly when multiple users mint shares
def test_multiple_mints(mock_gro_vault_usdc, alice, bob):
    mock_gro_vault_usdc.mint(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.balanceOf(alice) == 1000 * 1e6
    mock_gro_vault_usdc.mint(10_000 * 1e6, bob, {"from": bob})
    assert mock_gro_vault_usdc.balanceOf(bob) == 10_000 * 1e6


# Ensure user cannot request 0 shares to be minted
def test_no_zero_mints(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("ZeroAssets()")):
        mock_gro_vault_usdc.mint(0, alice, {"from": alice})


# Ensure user cannot mint shares over the deposit limit
@pytest.mark.skip(reason="Removed")
def test_deposit_limit_mint(mock_gro_vault_usdc, alice, admin):
    mock_gro_vault_usdc.setDepositLimit(1e6, {"from": admin})
    with brownie.reverts(error_string("OverDepositLimit()")):
        mock_gro_vault_usdc.mint(100 * 1e6, alice, {"from": alice})


# WITHDRAW/REDEEM TESTS

# user cannot request 0 assets to withdraw from the vault
def test_zero_withdrawrals(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("ZeroAssets()")):
        mock_gro_vault_usdc.withdraw(0, alice, alice, {"from": alice})


# user cannot withdraw more assets then they have shares for
def test_user_cannot_over_withdraw(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("InsufficientShares()")):
        mock_gro_vault_usdc.withdraw(1, alice, alice, {"from": alice})


# user cannot request 0 shares to redeem from the vault
def test_zero_redeem(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("ZeroShares()")):
        mock_gro_vault_usdc.redeem(0, alice, alice, {"from": alice})


# user cannot redeem more shares then they have
def test_user_cannot_over_redeem(mock_gro_vault_usdc, alice):
    with brownie.reverts(error_string("InsufficientShares()")):
        mock_gro_vault_usdc.redeem(1, alice, alice, {"from": alice})


# DEPOSIT/WITHDRAW LIMIT LOGIC TESTS

# check max deposit returns the correct value
def test_max_deposit(mock_gro_vault_usdc, alice):
    max_deposit = mock_gro_vault_usdc.maxDeposit(alice)
    assert max_deposit == MAX_UINT256


# check max deposit value changes as vault gets funded
def test_max_deposit_change(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(100 * 1e6, alice, {"from": alice})
    max_deposit = mock_gro_vault_usdc.maxDeposit(alice)
    assert max_deposit == MAX_UINT256 - 100000000


# check preview deposit returns the correct shares in the zero state
def test_preview_deposit_zero_state(mock_gro_vault_usdc):
    preview_deposit = mock_gro_vault_usdc.previewDeposit(200 * 1e6)
    assert preview_deposit == 200 * 1e6


# check preview deposit returns the correct shares after a deposit
def test_preview_deposit(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    preview_deposit = mock_gro_vault_usdc.previewDeposit(150 * 1e6)
    assert preview_deposit == 150 * 1e6


# check max mint returns the correct value
def test_max_mint(mock_gro_vault_usdc, alice):
    max_mint = mock_gro_vault_usdc.maxMint(alice)
    assert max_mint == MAX_UINT256

# check max mint returns the correct value
def test_max_mint_change(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(100 * 1e6, alice, {"from": alice})
    max_mint = mock_gro_vault_usdc.maxMint(alice)
    assert max_mint == MAX_UINT256 - 100000000

# check preview mint returns the correct amount of assets
# that would be deposited for said shares
def test_preview_mint(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(100 * 1e6, alice, {"from": alice})
    preview_mint = mock_gro_vault_usdc.previewMint(10 * 1e6)
    assert abs(preview_mint - 10 * 1e6) <= 1


# check user can withdraw the correct max amount of assets
def test_max_withdraw(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    max_withdraw = mock_gro_vault_usdc.maxWithdraw(alice)
    assert max_withdraw == 10000 * 1e6


# check preview withdraw returns the correct amount of shares
# required to withdraw the assets provided as the input
def test_preview_withdraw_zero_state(mock_gro_vault_usdc):
    preview_withdraw = mock_gro_vault_usdc.previewWithdraw(100 * 1e6)
    assert preview_withdraw == preview_withdraw


# check preview withdraw returns the correct amount of shares
# required to withdraw the assets provided as the input
def test_preview_withdraw(mock_gro_vault_usdc, alice):
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    preview_withdraw = mock_gro_vault_usdc.previewWithdraw(100 * 1e6)
    assert preview_withdraw == preview_withdraw


# check user can redeem the correct amount of assets
# for their total shares
def test_max_redeem(mock_gro_vault_usdc, alice):
    max_redeem = mock_gro_vault_usdc.maxRedeem(alice)
    assert max_redeem == 0
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    max_redeem = mock_gro_vault_usdc.maxRedeem(alice)
    assert max_redeem == 10000 * 1e6


# check user gets back the correct amount of assets
# for providing x number of shares
def test_preview_redeem(mock_gro_vault_usdc, alice):
    preview_redeem = mock_gro_vault_usdc.previewRedeem(1)
    assert preview_redeem == 1
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    preview_redeem = mock_gro_vault_usdc.previewRedeem(1e6)
    assert preview_redeem == 1e6


# VAULT ACCOUNTING LOGIC TESTS


def test_total_assets(
    mock_gro_vault_usdc,
    alice,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
):
    # no assets in vault
    total_assets = mock_gro_vault_usdc.totalAssets()
    assert total_assets == 0
    # assets after a deposit
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    total_assets = mock_gro_vault_usdc.totalAssets()
    assert total_assets == 1000 * 1e6
    # simulate profit from strategy to see change in total assets
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # send funds to strategies to simulate rewards
    mock_usdc.transfer(primary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    mock_usdc.transfer(secondary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    # simulate harvest for profits
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # check for correct total assets
    total_assets = mock_gro_vault_usdc.totalAssets()
    assert total_assets == 3000 * 1e6


def test_convert_to_shares(
    mock_gro_vault_usdc,
    alice,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
):
    # check correct value is returned when vault is empty
    assert mock_gro_vault_usdc.convertToShares(1e6) == 1e6
    # check correct value is returned when vault has funds
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.convertToShares(1e6) == 1e6
    # check correct value is returned when profits realised
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # send funds to strategies to simulate rewards
    mock_usdc.transfer(primary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    mock_usdc.transfer(secondary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    # simulate harvest for profits
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    assert mock_gro_vault_usdc.convertToShares(1e6) < 1e6


def test_convert_to_assets(
    mock_gro_vault_usdc,
    alice,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
):
    # check correct value is returned when vault is empty
    assert mock_gro_vault_usdc.convertToAssets(1e6) == 1e6
    # check correct value is returned when vault has funds
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.convertToAssets(1e6) == 1e6
    # check correct value is returned when profits realised
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # send funds to strategies to simulate rewards
    mock_usdc.transfer(primary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    mock_usdc.transfer(secondary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    # simulate harvest for profits
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    assert mock_gro_vault_usdc.convertToAssets(1e6) > 1e6


def test_price_per_share(
    mock_gro_vault_usdc,
    alice,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
):
    # 6 hours release time
    new_release_time = 6 * 60 * 60
    mock_gro_vault_usdc.setProfitRelease(new_release_time)
    # check correct value is returned when vault is empty
    assert mock_gro_vault_usdc.getPricePerShare() == 1e6
    # check correct value is returned when vault has funds
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    assert mock_gro_vault_usdc.getPricePerShare() == 1e6
    # check correct value is returned when profits realised
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # send funds to strategies to simulate rewards
    mock_usdc.transfer(primary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    mock_usdc.transfer(secondary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    # simulate harvest for profits
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    # complete slow release of profits (added a bit of buffer)
    brownie.chain.mine(timedelta=60 * 60 * 7)
    assert mock_gro_vault_usdc.getPricePerShare() == 3e6


# HARVEST LOGIC TESTS


@pytest.mark.skip(reason="Removed")
def test_strategy_harvest_trigger(
    mock_gro_vault_usdc,
    alice,
    admin,
    mock_usdc,
    primary_mock_strategy,
    secondary_mock_strategy,
):
    should_harvest = primary_mock_strategy.runHarvestTrigger()
    assert should_harvest is not True

    # simulate profits so harvest trigger returns true
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})
    mock_usdc.transfer(primary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    mock_usdc.transfer(secondary_mock_strategy.address, 1000 * 1e6, {"from": alice})
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})

    should_harvest = primary_mock_strategy.runHarvestTrigger()
    assert should_harvest is True
    should_harvest = secondary_mock_strategy.runHarvestTrigger()
    assert should_harvest is True


# STRATEGY LOGIC TESTS


def test_strategy_length(
    mock_gro_vault_usdc, primary_mock_strategy, secondary_mock_strategy
):
    # expect strategy length to be 2 due to fixtures
    assert mock_gro_vault_usdc.getNoOfStrategies() == 2


def test_set_debt_ratio(mock_gro_vault_usdc, admin, alice, primary_mock_strategy):
    # check non active strategy reverts
    with brownie.reverts(error_string("StrategyNotActive()")):
        mock_gro_vault_usdc.setDebtRatio(ZERO_ADDRESS, 0)
    # check non whitelisted address reverts
    with brownie.reverts("Ownable: caller is not the owner"):
        mock_gro_vault_usdc.setDebtRatio(
            primary_mock_strategy.address, 0, {"from": alice}
        )
    # check debt ratio cannot be over 100% across strategies
    with brownie.reverts(error_string("VaultDebtRatioTooHigh()")):
        mock_gro_vault_usdc.setDebtRatio(
            primary_mock_strategy.address, 11000, {"from": admin}
        )
    # check debt ratio correctly updates
    mock_gro_vault_usdc.setDebtRatio(
        primary_mock_strategy.address, 4000, {"from": admin}
    )
    assert (
        mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[DEBT_RATIO]
        == 4000
    )


def test_over_max_add_strategy(
    mock_gro_vault_usdc, admin, primary_mock_strategy, secondary_mock_strategy
):
    # deploy 3 test strategies
    test_strategy_3 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
    test_strategy_4 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
    test_strategy_5 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
    # add strategies to reach max limit
    mock_gro_vault_usdc.addStrategy(test_strategy_3.address, 0, {"from": admin})
    mock_gro_vault_usdc.addStrategy(test_strategy_4.address, 0, {"from": admin})
    mock_gro_vault_usdc.addStrategy(test_strategy_5.address, 0, {"from": admin})
    # test that by adding another strategy it reverts
    with brownie.reverts("typed error: 0xc6a56b50"):
        test_strategy_6 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_gro_vault_usdc.addStrategy(test_strategy_6.address, 0, {"from": admin})


def test_add_strategy(
    mock_gro_vault_usdc,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
):
    # check if adding strategy with zero address reverts
    with brownie.reverts(error_string("ZeroAddress()")):
        mock_gro_vault_usdc.addStrategy(ZERO_ADDRESS, 0, {"from": admin})
    # check you cannot add strategy that is already activated
    with brownie.reverts(error_string("StrategyActive()")):
        mock_gro_vault_usdc.addStrategy(
            primary_mock_strategy.address, 5000, {"from": admin}
        )
    # check you cannot add strategy with incorrect vault address
    with brownie.reverts(error_string("IncorrectVaultOnStrategy()")):
        mock_gro_vault_usdc_2 = admin.deploy(GVault, mock_usdc.address)
        test_strategy = admin.deploy(MockStrategy, mock_gro_vault_usdc_2.address)
        mock_gro_vault_usdc.addStrategy(test_strategy.address, 0, {"from": admin})
    # check debt ratio cannot be greater then 100%
    with brownie.reverts(error_string("VaultDebtRatioTooHigh()")):
        test_strategy = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_gro_vault_usdc.addStrategy(test_strategy.address, 1000, {"from": admin})
    # check min debt cannot be greater then max debt
    # with brownie.reverts("addStrategy: min > max"):
    #     test_strategy = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
    #     mock_gro_vault_usdc.addStrategy(
    #       test_strategy.address, 0, 2e6, 1e6, {"from": admin}
    #     )
    # check you can correctly add strategy (note initial debt ratio of zero)
    test_strategy = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
    mock_gro_vault_usdc.addStrategy(test_strategy.address, 0, {"from": admin})
    assert mock_gro_vault_usdc.withdrawalQueue(2) == test_strategy.address


def test_remove_strategy(mock_gro_vault_usdc, admin, primary_mock_strategy, alice):
    # check strategy in current withdraral queue
    assert primary_mock_strategy.address == mock_gro_vault_usdc.withdrawalQueue(0)
    # Do a deposit and strategy harvest to give strategy funds
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    primary_mock_strategy.runHarvest({"from": admin})
    # check current debt
    assert mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[TOTAL_DEBT] > 0
    # set maxDebtLimitPerHarvest to 0 and run harvest
    mock_gro_vault_usdc.setDebtRatio(primary_mock_strategy.address, 0, {"from": admin})
    primary_mock_strategy.runHarvest({"from": admin})
    # check current debt is zero
    assert (
        mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[TOTAL_DEBT] == 0
    )
    # run remove strategy
    mock_gro_vault_usdc.removeStrategy(primary_mock_strategy.address)
    assert primary_mock_strategy.address != mock_gro_vault_usdc.withdrawalQueue(0)
    mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[ACTIVE] is not True


def test_revoke_strategy(mock_gro_vault_usdc, primary_mock_strategy):
    # test that a strategy isn't active when revoked
    # mocking emergency exit by strategy calling revoke in testing
    assert mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[ACTIVE] is True
    mock_gro_vault_usdc.revokeStrategy({"from": primary_mock_strategy.address})
    assert (
        mock_gro_vault_usdc.strategies(primary_mock_strategy.address)[ACTIVE]
        is not True
    )


@pytest.mark.skip(reason="Removed")
def test_remove_and_add_strategy_from_queue(
    mock_gro_vault_usdc, primary_mock_strategy, admin, alice
):
    chain.snapshot()
    # test that we can remove an active strategy from the queue
    assert mock_gro_vault_usdc.withdrawalQueue(0) == primary_mock_strategy.address
    mock_gro_vault_usdc.removeStrategyFromQueue(
        primary_mock_strategy.address, {"from": admin}
    )
    assert mock_gro_vault_usdc.withdrawalQueue(0) != primary_mock_strategy.address
    chain.revert()

    # check removals cannot happen from an account that isn't whitelisted
    with brownie.reverts("removeStrategyFromQueue: !owner|whitelist"):
        mock_gro_vault_usdc.removeStrategyFromQueue(
            primary_mock_strategy.address, {"from": alice}
        )

    # test we can add back in the removed strategy from the queue
    mock_gro_vault_usdc.removeStrategyFromQueue(
        primary_mock_strategy.address, {"from": admin}
    )
    assert mock_gro_vault_usdc.withdrawalQueue(0) != primary_mock_strategy.address
    mock_gro_vault_usdc.addStrategyToQueue(
        primary_mock_strategy.address, {"from": admin}
    )
    assert mock_gro_vault_usdc.withdrawalQueue(1) == primary_mock_strategy.address
    chain.revert()

    # check additions cannot happen from an account that isn't whitelisted
    with brownie.reverts("addStrategyToQueue: !owner|whitelist"):
        mock_gro_vault_usdc.addStrategyToQueue(
            primary_mock_strategy.address, {"from": alice}
        )

    # check you cannot add a strategy that hasn't been acivated
    with brownie.reverts("addStrategyToQueue: !activated"):
        mock_new_strategy = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_gro_vault_usdc.addStrategyToQueue(
            mock_new_strategy.address, {"from": admin}
        )

    # check that you cannot add more strategies then the queue max
    with brownie.reverts("addStrategyToQueue: queue full"):
        # remove strategy to add back in later
        mock_gro_vault_usdc.removeStrategyFromQueue(
            primary_mock_strategy.address, {"from": admin}
        )
        # create new strategies to fill up the queue
        mock_new_strategy_2 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_new_strategy_3 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_new_strategy_4 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        mock_new_strategy_5 = admin.deploy(MockStrategy, mock_gro_vault_usdc.address)
        strategies = [
            mock_new_strategy_2,
            mock_new_strategy_3,
            mock_new_strategy_4,
            mock_new_strategy_5,
        ]
        # fill up the queue
        for strategy in strategies:
            mock_gro_vault_usdc.addStrategy(strategy.address, 0)

        # try to add back in strategy
        mock_gro_vault_usdc.addStrategyToQueue(
            primary_mock_strategy.address, {"from": admin}
        )

    # check you cannot add a strategy already in the queue
    chain.revert()
    with brownie.reverts("addStrategyToQueue: strategy already in queue"):
        mock_gro_vault_usdc.addStrategyToQueue(
            primary_mock_strategy.address, {"from": admin}
        )


def test_credit_available(
    mock_gro_vault_usdc,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
    alice,
):
    # take snapshot to be able to test both func signatures of credit available
    chain.snapshot()
    # check current credit
    credit_available = mock_gro_vault_usdc.creditAvailable(
        primary_mock_strategy.address, {"from": admin}
    )
    assert credit_available == 0
    # transfer funds to mock funds available for strategy
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    # check credit available has changed with a debt ratio of 50% for strategy
    credit_available = mock_gro_vault_usdc.creditAvailable(
        primary_mock_strategy.address, {"from": admin}
    )
    assert credit_available == 500 * 1e6
    # check the same as above but with diff func signature that is called from strategy
    chain.revert()
    credit_available = mock_gro_vault_usdc.creditAvailable(
        {"from": primary_mock_strategy.address}
    )
    assert credit_available == 0
    mock_gro_vault_usdc.deposit(1000 * 1e6, alice, {"from": alice})
    credit_available = mock_gro_vault_usdc.creditAvailable(
        {"from": primary_mock_strategy.address}
    )
    assert credit_available == 500 * 1e6


def test_strategy_debt(
    mock_gro_vault_usdc,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
    alice,
    bob,
):
    chain.snapshot()
    # test if a strategy shows the correct debt outstanding
    debt_outstanding = mock_gro_vault_usdc.excessDebt(primary_mock_strategy.address)
    assert debt_outstanding[0] == 0
    # fund vault then harvest to have funds sent to strategy
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    primary_mock_strategy.runHarvest({"from": admin})
    # mimic profits in the strategy
    mock_usdc.transfer(primary_mock_strategy.address, 10000 * 1e6, {"from": bob})
    # reduce the debt ratio of the strategy so it owes money to the vault
    mock_gro_vault_usdc.setDebtRatio(
        primary_mock_strategy.address, 1000, {"from": admin}
    )
    # check for the correct debt outstanding
    debt_outstanding = mock_gro_vault_usdc.excessDebt(primary_mock_strategy.address)
    assert debt_outstanding[0] == 4000 * 1e6

    # check the same as above but for the different func signature
    chain.revert()
    # test if a strategy shows the correct debt outstanding
    debt_outstanding = mock_gro_vault_usdc.excessDebt(primary_mock_strategy.address)
    assert debt_outstanding[0] == 0
    # fund vault then harvest to have funds sent to strategy
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    primary_mock_strategy.runHarvest({"from": admin})
    # mimic profits in the strategy
    mock_usdc.transfer(primary_mock_strategy.address, 10000 * 1e6, {"from": bob})
    # reduce the debt ratio of the strategy so it owes money to the vault
    mock_gro_vault_usdc.setDebtRatio(
        primary_mock_strategy.address, 1000, {"from": admin}
    )
    # check for the correct debt outstanding
    debt_outstanding = mock_gro_vault_usdc.excessDebt(primary_mock_strategy.address)
    assert debt_outstanding[0] == 4000 * 1e6

    # check the total strategy debt returns correctly
    strategy_debt = mock_gro_vault_usdc.strategyDebt(
        {"from": primary_mock_strategy.address}
    )
    assert strategy_debt == 5000 * 1e6

def test_strategy_withdrawal(
    mock_gro_vault_usdc,
    admin,
    primary_mock_strategy,
    secondary_mock_strategy,
    mock_usdc,
    alice,
    bob,
):
    chain.snapshot()
    # test if a strategy shows the correct debt outstanding
    debt_outstanding = mock_gro_vault_usdc.excessDebt(primary_mock_strategy.address)
    assert debt_outstanding[0] == 0
    # fund vault then harvest to have funds sent to strategy
    mock_gro_vault_usdc.deposit(10000 * 1e6, alice, {"from": alice})
    # reduce the debt ratio of the strategy so it owes money to the vault
    mock_gro_vault_usdc.setDebtRatio(
        primary_mock_strategy.address, 0, {"from": admin}
    )
    mock_gro_vault_usdc.setDebtRatio(
        secondary_mock_strategy.address, 10000, {"from": admin}
    )
    primary_mock_strategy.runHarvest({"from": admin})
    secondary_mock_strategy.runHarvest({"from": admin})

    assert primary_mock_strategy.estimatedTotalAssets() == 0
    assert secondary_mock_strategy.estimatedTotalAssets() > 0

    mock_gro_vault_usdc.withdraw(1000 * 1e6, alice, alice, {"from": alice})


def test_report(mock_gro_vault_usdc, primary_mock_strategy, mock_usdc, alice, bob):
    chain.snapshot()
    # the current version of the
    #   strategy uses estimated total assets for its report
    # Should not be possible for a strategy
    # to report a higher gain than actually available to the vault
    # with brownie.reverts(error_string("IncorrectStrategyAccounting()")):
    #     primary_mock_strategy.setTooMuchGain()
    #     mock_usdc.transfer(primary_mock_strategy.address, 10000 * 1e6, {"from": bob})
    #     primary_mock_strategy.runHarvest()
    # chain.revert()
    # Should not be possible for a strategy
    # to report a higher loss than actually possible to the vault
    with brownie.reverts(error_string("StrategyLossTooHigh()")):
        mock_gro_vault_usdc.deposit(10000 * 1e6, bob, {"from": bob})
        primary_mock_strategy.runHarvest()
        primary_mock_strategy.setTooMuchLoss()
        primary_mock_strategy._takeFunds(1000 * 1e6, {"from": bob})
        primary_mock_strategy.runHarvest()

    chain.revert()
    # PPS should decrease after a loss
    # to check loss reported correctly
    mock_gro_vault_usdc.deposit(10000 * 1e6, bob, {"from": bob})
    assert mock_gro_vault_usdc.getPricePerShare() == 1e6
    primary_mock_strategy.runHarvest()
    primary_mock_strategy._takeFunds(1000 * 1e6, {"from": bob})
    primary_mock_strategy.runHarvest()
    assert mock_gro_vault_usdc.getPricePerShare() < 1e6

    chain.revert()
    # PPS should increase after a loss
    # to check loss reported correctly
    mock_gro_vault_usdc.deposit(10000 * 1e6, bob, {"from": bob})
    assert mock_gro_vault_usdc.getPricePerShare() == 1e6
    primary_mock_strategy.runHarvest()
    # simulate reward
    mock_usdc.transfer(primary_mock_strategy.address, 10000 * 1e6, {"from": alice})
    primary_mock_strategy.runHarvest()
    chain.mine(timedelta=60 * 60 * 7)
    assert mock_gro_vault_usdc.getPricePerShare() > 1e6


# OTHERS TEST


# Test queue

# Given a vault zero or more strategies
# When a new strategy is added
# Then it should be the last item in the queue
def test_new_strategy_should_be_added_to_end(
    mock_gro_vault_usdc, admin, bot, next_mock_strategy
):
    assert mock_gro_vault_usdc.withdrawalQueue(0) == ZERO_ADDRESS
    strategy = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(strategy.address, 5000, {"from": admin})
    assert mock_gro_vault_usdc.withdrawalQueue(0) == strategy.address
    assert mock_gro_vault_usdc.withdrawalQueue(1) == ZERO_ADDRESS
    strategy_2 = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(strategy_2.address, 5000, {"from": admin})
    assert mock_gro_vault_usdc.withdrawalQueue(0) == strategy.address
    assert mock_gro_vault_usdc.withdrawalQueue(1) == strategy_2.address
    assert mock_gro_vault_usdc.withdrawalQueue(2) == ZERO_ADDRESS


# Given a vault with one or more strategies
# When a strategy removed
# Then the queue order should be updated
def test_removing_a_strategy_should_update_the_queue_order(
    mock_gro_vault_usdc, admin, bot, fill_queue
):
    for i, strategy in enumerate(fill_queue):
        assert mock_gro_vault_usdc.getStrategyPositions(strategy.address) == i
    mock_gro_vault_usdc.removeStrategy(fill_queue[0], {"from": admin})
    for i, strategy in enumerate(fill_queue[1:], 1):
        assert mock_gro_vault_usdc.getStrategyPositions(strategy.address) == i - 1


# Given a vault with zero or more strategies
# When a strategy added
# Then the id of the new strategy is unique
def test_strategy_should_have_a_unique_id_when_added(
    mock_gro_vault_usdc,
    admin,
    bot,
    primary_mock_strategy,
    secondary_mock_strategy,
    next_mock_strategy,
):
    fill_queue = [primary_mock_strategy, secondary_mock_strategy]
    ids = []
    for strategy in fill_queue:
        ids.append(mock_gro_vault_usdc.strategyId(strategy.address))
    strategy_new = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(strategy_new.address, 0, {"from": admin})
    assert mock_gro_vault_usdc.strategyId(strategy_new.address) not in ids


# Given a vault with one or more strategies
# When a strategy is removed and another one is added
# Then the id of the new strategy is unique
def test_strategy_should_have_a_unique_id_when_added_part_2(
    mock_gro_vault_usdc, admin, bot, fill_queue, next_mock_strategy
):
    ids = []
    for strategy in fill_queue:
        ids.append(mock_gro_vault_usdc.strategyId(strategy.address))
    mock_gro_vault_usdc.removeStrategy(fill_queue[3], {"from": admin})
    strategy_new = next_mock_strategy()
    mock_gro_vault_usdc.addStrategy(strategy_new.address, 1000, {"from": admin})
    assert mock_gro_vault_usdc.strategyId(strategy_new.address) not in ids


# Given a vault with one or more strategies
# When a new strategy is moved
# Then the strategy should end up in the desired position
def test_it_should_be_possible_to_move_strategy(
    mock_gro_vault_usdc, admin, bot, fill_queue
):
    strat_4 = fill_queue[3]
    assert mock_gro_vault_usdc.getStrategyPositions(strat_4.address) == 3
    mock_gro_vault_usdc.moveStrategy(strat_4.address, 1)
    assert mock_gro_vault_usdc.getStrategyPositions(strat_4.address) == 1
    mock_gro_vault_usdc.moveStrategy(strat_4.address, 2)
    assert mock_gro_vault_usdc.getStrategyPositions(strat_4.address) == 2


# Given a vault with one or more strategies
# When a strategy is moved to the same position
# Then it should remain there
def test_it_should_not_move_the_strategy_if_same_pos_specified(
    mock_gro_vault_usdc, admin, bot, fill_queue
):
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[4].address) == 4
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[3].address) == 3
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[2].address) == 2
    with brownie.reverts():
        mock_gro_vault_usdc.moveStrategy(fill_queue[3], 3, {"from": admin})
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[4].address) == 4
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[3].address) == 3
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[2].address) == 2


# Given a vault with one or more strategies
# When a strategy is moved backwards in the queue
# Then it should not be possible to move the strategy beyond the tail position
def test_it_should_not_be_possible_to_move_tail_further_back(
    mock_gro_vault_usdc, admin, bot, fill_queue
):
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[0].address) == 0
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[4].address) == 4
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[1].address) == 1
    mock_gro_vault_usdc.moveStrategy(fill_queue[0], 100, {"from": admin})
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[0].address) == 4
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[4].address) == 3
    assert mock_gro_vault_usdc.getStrategyPositions(fill_queue[1].address) == 0

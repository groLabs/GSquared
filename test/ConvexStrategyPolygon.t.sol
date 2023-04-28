// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {BaseSetup} from "./Base.GSquared.t.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import {ERC20} from "../contracts/solmate/src/tokens/ERC20.sol";
import "./utils/utils.sol";
import "../contracts/GRouter.sol";
import "../contracts/GVault.sol";
import "../contracts/GTranche.sol";
import "../contracts/GMigration.sol";
import "../contracts/strategy/ConvexStrategyPolygon.sol";
import "../contracts/oracles/CurveOracle.sol";
import "../contracts/strategy/stop-loss/StopLossLogic.sol";
import "../contracts/oracles/RouterOracle.sol";
import "../contracts/tokens/JuniorTranche.sol";
import "../contracts/tokens/SeniorTranche.sol";
import "../contracts/pnl/PnLFixedRate.sol";
import "../contracts/solmate/src/utils/SafeTransferLib.sol";

// Polygon CVX Strategy integration test
contract ConvexStrategyPolygonTest is BaseSetup {
    using SafeTransferLib for ERC20;

    address public constant THREE_POOL_POLYGON =
        address(0x445FE580eF8d70FF569aB36e80c647af338db351);
    ERC20 public constant THREE_POOL_TOKEN_POLYGON =
        ERC20(address(0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171));
    ERC20 public constant AM_THREE_POOL_TOKEN_POLYGON =
        ERC20(address(0x19793B454D3AfC7b454F206Ffe95aDE26cA6912c));
    ERC20 internal constant DAI_POLY =
        ERC20(address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063));
    ERC20 internal constant USDC_POLY =
        ERC20(address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174));
    ERC20 internal constant USDT_POLY =
        ERC20(address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F));
    ERC20 internal constant USDR =
        ERC20(address(0xb5DFABd7fF7F83BAB83995E72A52B97ABb7bcf63));
    address constant USDR_DEPLOYER =
        address(0x3d41487A3c5662eDE90D0eE8854f3cC59E8D66AD);
    uint256 public constant USDR_LP_PID = 11;
    address public constant USDR_LP =
        address(0xa138341185a9D0429B0021A11FB717B225e13e1F);

    ConvexStrategyPolygon cvxStrategy;
    StopLossLogic snl;

    address public basedAddress;

    function setUp() public override {
        // do nothing if chain is not polygon:
        if (block.chainid != 137) {
            return;
        }
        utils = new Utils();
        users = utils.createUsers(5);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        joe = users[2];

        basedAddress = users[4];
        vm.label(basedAddress, "Based");
        CHAINLINK_AGG_ADDRESSES[0] = address(
            0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D // DAI
        );
        CHAINLINK_AGG_ADDRESSES[1] = address(
            0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7 // USDC
        );
        CHAINLINK_AGG_ADDRESSES[2] = address(
            0x0A6513e40db6EB1b165753AD52E80663aeA50545 // USDT
        );
        vm.startPrank(basedAddress);

        GVT = new JuniorTranche("GVT", "GVT");
        PWRD = new SeniorTranche("PWRD", "PWRD");
        curveOracle = new CurveOracle();
        gVault = new GVault(THREE_POOL_TOKEN_POLYGON);
        StopLossLogic snl = new StopLossLogic();
        cvxStrategy = new ConvexStrategyPolygon(
            IGVault(address(gVault)),
            basedAddress,
            USDR_LP_PID,
            USDR_LP
        );
        cvxStrategy.setStopLossLogic(address(snl));
        snl.setStrategy(address(cvxStrategy), 1e18, 400);
        cvxStrategy.setKeeper(basedAddress);
        gVault.addStrategy(address(cvxStrategy), 10000);

        TRANCHE_TOKENS[0] = address(GVT);
        TRANCHE_TOKENS[1] = address(PWRD);
        YIELD_VAULTS.push(address(gVault));

        gTranche = new GTranche(
            YIELD_VAULTS,
            TRANCHE_TOKENS,
            IOracle(curveOracle),
            GMigration(ZERO)
        );

        pnl = new PnLFixedRate(address(gTranche));
        GVT.setController(address(gTranche));
        GVT.addToWhitelist(address(gTranche));
        PWRD.setController(address(gTranche));
        PWRD.addToWhitelist(address(gTranche));

        gTranche.setPnL(pnl);
        routerOracle = new RouterOracle(CHAINLINK_AGG_ADDRESSES);
        gRouter = new GRouter(
            gTranche,
            gVault,
            routerOracle,
            ICurve3Pool(THREE_POOL_POLYGON),
            ERC20(THREE_POOL_TOKEN_POLYGON)
        );
        vm.stopPrank();
    }

    /// @dev Polygon chain id is 137
    /// Abort execution of test in case local fork is not forked from polygon
    modifier polyOnly() {
        // do nothing if chain is not polygon:
        if (block.chainid != 137) {
            return;
        } else {
            _;
        }
    }

    function genThreeCrv(uint256 amount, address _user)
        public
        override
        returns (uint256)
    {
        vm.startPrank(_user);
        DAI_POLY.approve(THREE_POOL_POLYGON, amount);
        USDC_POLY.approve(THREE_POOL_POLYGON, amount);
        if (
            ERC20(address(USDT_POLY)).allowance(_user, THREE_POOL_POLYGON) > 0
        ) {
            ERC20(address(USDT_POLY)).safeApprove(THREE_POOL_POLYGON, 0);
        }
        ERC20(address(USDT_POLY)).safeApprove(THREE_POOL_POLYGON, amount);
        uint256 dai = amount;
        uint256 usdt = amount / 10**12;
        uint256 usdc = amount / 10**12;
        setStorage(
            _user,
            DAI_POLY.balanceOf.selector,
            address(DAI_POLY),
            type(uint256).max
        );
        setStorage(
            _user,
            USDC_POLY.balanceOf.selector,
            address(USDC_POLY),
            type(uint256).max
        );
        setStorage(
            _user,
            USDT_POLY.balanceOf.selector,
            address(USDT_POLY),
            type(uint256).max
        );
        ICurve3Pool(THREE_POOL_POLYGON).add_liquidity(
            [dai, usdc, usdt],
            0,
            true
        );

        vm.stopPrank();

        return THREE_POOL_TOKEN_POLYGON.balanceOf(_user);
    }

    function depositIntoVault(address _user, uint256 _amount)
        public
        override
        returns (uint256 shares)
    {
        uint256 balance = genThreeCrv(_amount, _user);
        vm.startPrank(_user);
        THREE_POOL_TOKEN_POLYGON.approve(address(gVault), balance);
        shares = gVault.deposit(balance, _user);
        vm.stopPrank();
    }

    // Deal USDR to based address so it can do manipulation shenanigans
    function _dealUSDR() internal {
        vm.startPrank(USDR_DEPLOYER);
        USDR.transfer(basedAddress, 1e7);
        vm.stopPrank();
    }

    // @dev Manipulate the pool
    // @param profit True if we want to make a profit, false if we want to lose money
    // @param change The percentage of the pool we want to change
    // @param pool The pool we want to manipulate
    // @param token The token we want to manipulate, should be 3Pool token usually
    // @param underlyingToken The underlying token of the pool such as Aave 3pool token
    function manipulateMetaPoolOnPoly(
        bool profit,
        uint256 change,
        address pool,
        address token,
        address underlyingToken
    ) public {
        uint256 tokenAmount = ERC20(underlyingToken).balanceOf(pool);
        tokenAmount = ((tokenAmount * 10000) / (10000 - change));
        // Give 3pool token
        genStable(tokenAmount, address(token), basedAddress);
        // Give USDR to based address
        _dealUSDR();
        vm.startPrank(basedAddress);
        THREE_POOL_TOKEN_POLYGON.approve(pool, type(uint256).max);
        uint256 amount;
        if (profit) {
            amount = ICurveMeta(pool).exchange(1, 0, tokenAmount, 0);
        } else {
            amount = ICurveMeta(pool).exchange(0, 1, tokenAmount, 0);
        }
        vm.stopPrank();
    }

    function testHappyDepositAndHarvest(uint256 deposit) public polyOnly {
        vm.assume(deposit > 1E20);
        vm.assume(deposit < 1E22);
        depositIntoVault(alice, deposit);
        uint256 initEstimatedAssets = cvxStrategy.estimatedTotalAssets();
        // Make sure that strategy didn't invest any assets yet
        assertEq(initEstimatedAssets, 0);
        vm.startPrank(basedAddress);
        cvxStrategy.runHarvest();
        // Make sure assets appear in the strategy
        assertGt(cvxStrategy.estimatedTotalAssets(), initEstimatedAssets);
        vm.stopPrank();
    }

    function testStrategyProfit(uint128 _deposit, uint16 _profit)
        public
        polyOnly
    {
        uint256 deposit = uint256(_deposit);
        uint256 profit = uint256(_profit);
        vm.assume(deposit > 1E20);
        vm.assume(deposit < 1E22);
        vm.assume(profit > 500);
        vm.assume(profit < 10000);
        uint256 shares = depositIntoVault(alice, deposit);
        vm.startPrank(basedAddress);
        cvxStrategy.runHarvest();
        cvxStrategy.setBaseSlippage(1000);
        vm.stopPrank();

        uint256 initEstimatedAssets = cvxStrategy.estimatedTotalAssets();
        uint256 initVaultAssets = gVault.realizedTotalAssets();
        manipulateMetaPoolOnPoly(
            true,
            profit,
            USDR_LP,
            address(THREE_POOL_TOKEN_POLYGON),
            address(AM_THREE_POOL_TOKEN_POLYGON)
        );
        // Make sure that estimated assets increased after profit
        assertGt(cvxStrategy.estimatedTotalAssets(), initEstimatedAssets);
        // Make sure that vault assets didn't change
        assertEq(gVault.realizedTotalAssets(), initVaultAssets);
        // Run harvest again to realize profit
        vm.startPrank(basedAddress);
        cvxStrategy.runHarvest();
        // Make sure profit is realized
        assertGt(cvxStrategy.estimatedTotalAssets(), initEstimatedAssets);
        assertGt(gVault.realizedTotalAssets(), initVaultAssets);

        vm.stopPrank();
    }
}

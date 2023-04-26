// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import {ERC20} from "../contracts/solmate/src/tokens/ERC20.sol";
import "./utils/utils.sol";
import "../contracts/GRouter.sol";
import "../contracts/GVault.sol";
import "../contracts/GTranche.sol";
import "../contracts/GMigration.sol";
import "../contracts/strategy/ConvexStrategyPolygon.sol";
import "../contracts/oracles/CurveOracle.sol";
import "../contracts/oracles/RouterOracle.sol";
import "../contracts/tokens/JuniorTranche.sol";
import "../contracts/tokens/SeniorTranche.sol";
import "../contracts/pnl/PnLFixedRate.sol";
import "../contracts/mocks/MockStrategy.sol";

// Polygon CVX Strategy integration test
contract ConvexStrategyPolygonTest is Test {
    address public constant THREE_POOL =
        address(0x445FE580eF8d70FF569aB36e80c647af338db351);
    ERC20 public constant THREE_POOL_TOKEN =
        ERC20(address(0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171));

    address constant ZERO = address(0x0000000000000000000000000000000000000000);
    uint256 public constant usdr_lp_pid = 11;
    address public constant usdr_lp =
        address(0xa138341185a9D0429B0021A11FB717B225e13e1F);

    GTranche gTranche;
    GVault gVault;
    ConvexStrategyPolygon strategy;
    CurveOracle curveOracle;
    GRouter gRouter;
    RouterOracle routerOracle;
    PnLFixedRate pnl;
    JuniorTranche GVT;
    SeniorTranche PWRD;
    Utils internal utils;

    address[3] public CHAINLINK_AGG_ADDRESSES;
    address[2] public TRANCHE_TOKENS;
    address[] public YIELD_VAULTS;
    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal joe;
    address internal torsten;
    address internal based;

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

    function setUp() public virtual {
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
        vm.label(joe, "Joe");
        torsten = users[3];
        vm.label(torsten, "Torsten");

        based = users[4];
        vm.label(based, "Based");
        CHAINLINK_AGG_ADDRESSES[0] = address(
            0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D // DAI
        );
        CHAINLINK_AGG_ADDRESSES[1] = address(
            0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7 // USDC
        );
        CHAINLINK_AGG_ADDRESSES[2] = address(
            0x0A6513e40db6EB1b165753AD52E80663aeA50545 // USDT
        );
        vm.startPrank(based);

        GVT = new JuniorTranche("GVT", "GVT");
        PWRD = new SeniorTranche("PWRD", "PWRD");
        curveOracle = new CurveOracle();
        gVault = new GVault(THREE_POOL_TOKEN);
        strategy = new ConvexStrategyPolygon(
            IGVault(address(gVault)),
            based,
            usdr_lp_pid,
            usdr_lp
        );
        gVault.addStrategy(address(strategy), 10000);

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
            ICurve3Pool(THREE_POOL),
            ERC20(THREE_POOL_TOKEN)
        );
        vm.stopPrank();
    }

    function testDummy() public polyOnly {
        console2.log("Hello!");
    }
}

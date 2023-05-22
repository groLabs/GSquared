import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/interfaces/IERC20.sol";
import "./utils/utils.sol";
import "./Base.GSquared.t.sol";
import {ArbOusd} from "../contracts/ArbOusd.sol";
import "forge-std/console2.sol";

// Base fixture
contract arbTest is Test, BaseSetup {
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;
    ConvexStrategy public convexStrategy;
    GVault public gVaultMainnet;
    ArbOusd arb;

    function setUp() public override {
        utils = new Utils();
        users = utils.createUsers(4);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        joe = users[2];
        vm.label(joe, "Joe");
        torsten = users[3];
        vm.label(torsten, "Torsten");

        vm.deal(BASED_ADDRESS, 100000e18);
        vm.startPrank(BASED_ADDRESS);
        convexStrategy = ConvexStrategy(
            address(0x73703f0493C08bA592AB1e321BEaD695AC5b39E3)
        ); // OUSD cvx strat
        gVaultMainnet = GVault(
            address(0x1402c1cAa002354fC2C4a4cD2b4045A5b9625EF3)
        );
        arb = new ArbOusd();
        vm.stopPrank();
        genThreeCrv(2e23, BASED_ADDRESS);
    }

    function testArb() public {
        vm.startPrank(BASED_ADDRESS);
        convexStrategy.setBaseSlippage(500);
        THREE_POOL_TOKEN.approve(address(arb), MAX_UINT);
        arb.performArbWithTransfer(THREE_POOL_TOKEN.balanceOf(BASED_ADDRESS));
        // Run arb multiple times:
        for (uint256 i = 0; i < 8; ++i) {
            console2.log("Running arb iteration: ", i + 1);
            (uint256 initialBal, uint256 finalBal) = arb.performArb(50);
            if (finalBal < initialBal) {
                console2.log("Difference between 3crvs", initialBal - finalBal);
            } else {
                console2.log("Difference between 3crvs", finalBal - initialBal);
            }
            (
                ,
                ,
                ,
                uint256 totalDebt,
                uint256 totalGain,
                uint256 totalLoss
            ) = gVaultMainnet.strategies(address(convexStrategy));
            console2.log("Total debt", totalDebt);
            console2.log("Total gain", totalGain);
            console2.log("Total loss", totalLoss);
            convexStrategy.runHarvest();
        }
        vm.stopPrank();
    }
}

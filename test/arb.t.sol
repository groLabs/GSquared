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

    address public constant VAULT_OWNER =
        address(0x359F4fe841f246a095a82cb26F5819E10a91fe0d);

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
        // Reduce strategy base ratio
        (, uint256 debtRatio, , , , ) = gVaultMainnet.strategies(
            address(convexStrategy)
        );
        console2.log("Initial debt ration", debtRatio);
        vm.stopPrank();
        vm.prank(VAULT_OWNER);
        gVaultMainnet.setDebtRatio(address(convexStrategy), debtRatio - 224);
        // Run arb multiple times:
        for (uint256 i = 0; i < 8; ++i) {
            vm.startPrank(BASED_ADDRESS);
            console2.log("Running arb iteration: ", i + 1);
            (uint256 initialBal, uint256 finalBal) = arb.performArb(120);
            (
                ,
                uint256 debtRatio,
                ,
                uint256 totalDebt,
                uint256 totalGain,
                uint256 totalLoss
            ) = gVaultMainnet.strategies(address(convexStrategy));
            vm.stopPrank();
            console2.log("Current debt ratio is", debtRatio);
            vm.prank(VAULT_OWNER);
            uint256 settingDebtRatio = debtRatio > 224 ? debtRatio - 224 : 0;
            gVaultMainnet.setDebtRatio(
                address(convexStrategy),
                settingDebtRatio
            );
            console2.log("Total debt", totalDebt);
            console2.log("Total gain", totalGain);
            console2.log("Total loss", totalLoss);

            vm.startPrank(BASED_ADDRESS);
            convexStrategy.runHarvest();
            vm.stopPrank();
        }

        // Make sure strategy debtRatio is 0 now:
        (, uint256 debtRatioFinal, , , , ) = gVaultMainnet.strategies(
            address(convexStrategy)
        );
        assertEq(debtRatioFinal, 0);
    }
}

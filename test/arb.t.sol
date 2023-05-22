import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/interfaces/IERC20.sol";
import "./utils/utils.sol";
import "./Base.GSquared.t.sol";
import {OUSDArb} from "../contracts/ArbOusd.sol";
import "forge-std/console2.sol";

// Base fixture
contract arbTest is Test, BaseSetup {
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;
    OUSDArb arb;

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
        arb = new OUSDArb();
        vm.stopPrank();
        genThreeCrv(2e23, BASED_ADDRESS);
    }

    function testArb() public {
        vm.startPrank(BASED_ADDRESS);
        console2.log('1');
        THREE_POOL_TOKEN.approve(address(arb), MAX_UINT);
        console2.log('2');
        arb.performArbWithTransfer(THREE_POOL_TOKEN.balanceOf(BASED_ADDRESS));
        vm.stopPrank();
    }
}

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../contracts/GVault.sol";
import "../contracts/strategy/ConvexStrategy.sol";
import "../contracts/strategy/ConvexStrategyFactory.sol";

contract Benchmark is Test {
    uint256 frax_lp_pid = 32;
    address frax_lp = address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    uint32 public constant NUM_OF_STRATS_TO_DEPLOY = 20;
    ERC20 public constant THREE_POOL_TOKEN =
        ERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));

    GVault gVault;
    ConvexStrategyFactory factory;

    function setUp() public {
        gVault = new GVault(THREE_POOL_TOKEN);
        ConvexStrategy strategyImpl = new ConvexStrategy();
        factory = new ConvexStrategyFactory(address(strategyImpl));
    }

    function testBenchmark() public {
        for (uint256 i = 0; i < NUM_OF_STRATS_TO_DEPLOY; i++) {
            ConvexStrategy strategy = ConvexStrategy(
                factory.createProxyStrategy(
                    IGVault(address(gVault)),
                    address(this),
                    frax_lp_pid,
                    frax_lp
                )
            );
        }
    }
}

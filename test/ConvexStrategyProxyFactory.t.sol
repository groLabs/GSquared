import "./Base.GSquared.t.sol";
import "../contracts/strategy/ConvexStrategy.sol";
import "../contracts/strategy/ConvexStrategyFactory.sol";

contract ConvexStrategyFactoryTest is BaseSetup {
    ConvexStrategy strategyImpl;

    function setUp() public virtual override {
        BaseSetup.setUp();
        strategyImpl = new ConvexStrategy();
    }

    // Simple test to deploy strat and check the owner and implementation
    function testFactoryDeployHappy() public {
        ConvexStrategyFactory factory = new ConvexStrategyFactory(
            address(strategyImpl)
        );
        address strategy = factory.createProxyStrategy(
            IGVault(address(gVault)),
            address(this),
            32,
            address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B)
        );

        ConvexStrategy proxy = ConvexStrategy(strategy);
        assert(proxy.owner() == address(this));
        assert(factory.getImplementation() == address(strategyImpl));
    }

    function testFactorySetImplementationHappy() public {
        ConvexStrategy newImpl = new ConvexStrategy();
        ConvexStrategyFactory factory = new ConvexStrategyFactory(
            address(strategyImpl)
        );
        factory.setImplementation(address(newImpl));
        assert(factory.getImplementation() == address(newImpl));
    }

    function testFactorySetImplementationNotOwner() public {
        ConvexStrategy newImpl = new ConvexStrategy();
        address payable stranger = utils.getNextUserAddress();
        vm.prank(stranger);
        ConvexStrategyFactory factory = new ConvexStrategyFactory(
            address(strategyImpl)
        );
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setImplementation(address(newImpl));
        vm.stopPrank;
    }

    function testFactoryInitializeAgainFail() public {
        ConvexStrategyFactory factory = new ConvexStrategyFactory(
            address(strategyImpl)
        );
        address strategy = factory.createProxyStrategy(
            IGVault(address(gVault)),
            address(this),
            32,
            address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B)
        );

        ConvexStrategy proxy = ConvexStrategy(strategy);
        // Try to initialize proxy again and expect it to fail:
        vm.expectRevert("Initializable: contract is already initialized");
        proxy.initialize(
            IGVault(address(gVault)),
            address(this),
            32,
            address(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B)
        );
    }
}

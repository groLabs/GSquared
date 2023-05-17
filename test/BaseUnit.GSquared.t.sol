import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/interfaces/IERC20.sol";
import "./utils/utils.sol";
import "../contracts/interfaces/IPnL.sol";
import "../contracts/interfaces/IOracle.sol";
import "../contracts/GRouter.sol";
import "../contracts/GVault.sol";
import "../contracts/GTranche.sol";
import "../contracts/pnl/PnLFixedRate.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockDAI.sol";
import "../contracts/mocks/MockUSDC.sol";
import "../contracts/mocks/MockUSDT.sol";
import "../contracts/mocks/MockUSDT.sol";
import "../contracts/mocks/MockStrategy.sol";
import "../contracts/mocks/MockCurveOracle.sol";
import "../contracts/mocks/MockThreePoolCurve.sol";
import "../contracts/solmate/src/utils/SafeTransferLib.sol";
import "../contracts/solmate/src/utils/CREATE3.sol";
import {TokenCalculations} from "../contracts/common/TokenCalculations.sol";
import "../contracts/solmate/src/utils/CREATE3.sol";

contract Mock3CRV is MockERC20 {
    constructor() ERC20("3crv", "3crv", 6) {}

    function faucet() external override {
        _mint(msg.sender, 10000e18);
    }
}

contract BaseUnitFixture is Test {
    using stdStorage for StdStorage;
    using SafeTransferLib for ERC20;

    address[] public YIELD_VAULTS;

    GTranche public gTranche;
    GVault public gVault;
    MockStrategy public strategy;
    IOracle public curveOracle;
    GRouter public gRouter;
    PnLFixedRate public pnl;
    MockERC20 public threeCurveToken;
    Utils internal utils;
    MockThreePoolCurve public threePoolCurve;
    MockERC20 public dai;
    MockERC20 public usdt;
    MockERC20 public usdc;

    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal joe;
    address internal torsten;

    function arbitraryCreate(
        bytes32 salt,
        bytes memory creationCode,
        uint256 ethValue
    ) public returns (address) {
        return CREATE3.deploy(salt, creationCode, ethValue);
    }

    function setUp() public virtual {
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

        bytes32 salt = bytes32(uint256(block.number));
        address tokenLogic = arbitraryCreate(
            salt,
            type(TokenCalculations).creationCode,
            1e18
        );
        MockThreePoolCurve threePoolCurve = new MockThreePoolCurve();
        MockERC20 threeCurveToken = new Mock3CRV();
        MockERC20 dai = new MockDAI();
        MockERC20 usdc = new MockUSDC();
        MockERC20 usdt = new MockUSDT();
        curveOracle = new MockCurveOracle();
        gVault = new GVault(threeCurveToken);
        strategy = new MockStrategy(address(gVault));
        gVault.addStrategy(address(strategy), 10000);
        YIELD_VAULTS.push(address(gVault));

        gTranche = new GTranche(
            YIELD_VAULTS,
            IOracle(curveOracle),
            ITokenLogic(tokenLogic)
        );
        pnl = new PnLFixedRate(address(gTranche));
        gTranche.setPnL(pnl);
        address[3] memory tokens = [address(dai), address(usdc), address(usdt)];
        gRouter = new GRouter(
            gTranche,
            gVault,
            MockThreePoolCurve(address(threePoolCurve)),
            ERC20(threeCurveToken)
        );
    }
}

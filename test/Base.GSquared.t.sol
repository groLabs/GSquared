import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "./utils/utils.sol";
import "../contracts/GRouter.sol";
import "../contracts/GVault.sol";
import "../contracts/GTranche.sol";
import "../contracts/GMigration.sol";
import "../contracts/oracles/CurveOracle.sol";
import "../contracts/oracles/RouterOracle.sol";
import "../contracts/tokens/JuniorTranche.sol";
import "../contracts/tokens/SeniorTranche.sol";
import "../contracts/pnl/PnLFixedRate.sol";
import "../contracts/strategy/stop-loss/StopLossLogic.sol";
import "../contracts/strategy/keeper/GStrategyGuard.sol";
import "../contracts/strategy/keeper/GStrategyResolver.sol";
import "../contracts/mocks/MockStrategy.sol";
import "../contracts/strategy/ConvexStrategy.sol";

interface IConvexRewards {
    function rewardRate() external view returns (uint256);

    function periodFinish() external view returns (uint256);
}

contract BaseSetup is Test {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    address public constant THREE_POOL =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ERC20 public constant THREE_POOL_TOKEN =
        ERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));
    ERC20 public constant DAI =
        ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    ERC20 public constant USDC =
        ERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    ERC20 public constant USDT =
        ERC20(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    address constant COFFEE_ADDRESS =
        address(0xc0ffEE4a95F15ff9973A17E563a8A8701D719890);
    address constant BASED_ADDRESS =
        address(0xBA5EDF9dAd66D9D81341eEf8131160c439dbA91B);
    address constant ZERO = address(0x0000000000000000000000000000000000000000);
    uint256 constant MAX_UINT = type(uint256).max;
    uint256 constant MIN_DELAY = 259200;

    address[3] public CHAINLINK_AGG_ADDRESSES;
    address[2] public TRANCHE_TOKENS;
    address[] public YIELD_VAULTS;

    GTranche gTranche;
    GVault gVault;
    MockStrategy strategy;
    CurveOracle curveOracle;
    GRouter gRouter;
    RouterOracle routerOracle;
    PnLFixedRate pnl;
    JuniorTranche GVT;
    SeniorTranche PWRD;

    Utils internal utils;

    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal joe;
    address internal torsten;

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

        CHAINLINK_AGG_ADDRESSES[0] = address(
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9
        );
        CHAINLINK_AGG_ADDRESSES[1] = address(
            0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
        );
        CHAINLINK_AGG_ADDRESSES[2] = address(
            0x3E7d1eAB13ad0104d2750B8863b489D65364e32D
        );

        vm.startPrank(BASED_ADDRESS);

        GVT = new JuniorTranche("GVT", "GVT");
        PWRD = new SeniorTranche("PWRD", "PWRD");
        curveOracle = new CurveOracle();
        gVault = new GVault(THREE_POOL_TOKEN);
        strategy = new MockStrategy(address(gVault));
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

    function findStorage(
        address _user,
        bytes4 _selector,
        address _contract
    ) public returns (uint256) {
        uint256 slot = stdstore
            .target(_contract)
            .sig(_selector)
            .with_key(_user)
            .find();
        bytes32 data = vm.load(_contract, bytes32(slot));
        return uint256(data);
    }

    function setStorage(
        address _user,
        bytes4 _selector,
        address _contract,
        uint256 value
    ) public {
        uint256 slot = stdstore
            .target(_contract)
            .sig(_selector)
            .with_key(_user)
            .find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    function prepUser(address _user) internal {
        vm.startPrank(_user);
        DAI.approve(address(gRouter), MAX_UINT);
        GVT.approve(address(gRouter), MAX_UINT);
        PWRD.approve(address(gRouter), MAX_UINT);
        setStorage(
            _user,
            DAI.balanceOf.selector,
            address(DAI),
            type(uint256).max
        );
        vm.stopPrank();
    }

    function prepUserCrv(address _user) internal {
        vm.startPrank(_user);
        DAI.approve(address(THREE_POOL), MAX_UINT);
        THREE_POOL_TOKEN.approve(address(gVault), MAX_UINT);
        GVT.approve(address(gTranche), MAX_UINT);
        PWRD.approve(address(gTranche), MAX_UINT);
        ERC20(address(gVault)).approve(address(gTranche), MAX_UINT);
        setStorage(
            _user,
            DAI.balanceOf.selector,
            address(DAI),
            type(uint256).max
        );
        vm.stopPrank();
    }

    function delta(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function genThreeCrv(uint256 amount, address _user)
        public
        returns (uint256)
    {
        vm.startPrank(_user);
        DAI.approve(THREE_POOL, amount);
        USDC.approve(THREE_POOL, amount);
        if (IERC20(address(USDT)).allowance(_user, THREE_POOL) > 0) {
            IERC20(address(USDT)).safeApprove(THREE_POOL, 0);
        }
        IERC20(address(USDT)).safeApprove(THREE_POOL, amount);
        uint256 dai = amount;
        uint256 usdt = amount / 10**12;
        uint256 usdc = amount / 10**12;
        setStorage(
            _user,
            DAI.balanceOf.selector,
            address(DAI),
            type(uint256).max
        );
        setStorage(
            _user,
            USDC.balanceOf.selector,
            address(USDC),
            type(uint256).max
        );
        setStorage(
            _user,
            USDT.balanceOf.selector,
            address(USDT),
            type(uint256).max
        );

        ICurve3Pool(THREE_POOL).add_liquidity([dai, usdc, usdt], 0);

        vm.stopPrank();

        return THREE_POOL_TOKEN.balanceOf(_user);
    }

    function genStable(
        uint256 amount,
        address token,
        address _user
    ) public {
        setStorage(
            _user,
            IERC20(token).balanceOf.selector,
            token,
            type(uint256).max
        );
    }

    function manipulatePool(
        bool profit,
        uint256 change,
        address pool,
        address token
    ) public {
        uint256 tokenAmount = IERC20(token).balanceOf(pool);
        tokenAmount = ((tokenAmount * 10000) / (10000 - change)) * 10;
        genStable(tokenAmount, token, BASED_ADDRESS);

        vm.startPrank(BASED_ADDRESS);
        IERC20(token).approve(pool, type(uint256).max);
        if (profit) {
            ICurveMeta(pool).add_liquidity([0, tokenAmount], 0);
        } else {
            ICurveMeta(pool).add_liquidity([tokenAmount, 0], 0);
        }
        vm.stopPrank();
    }

    function depositIntoVault(address _user, uint256 _amount)
        public
        returns (uint256 shares)
    {
        uint256 balance = genThreeCrv(_amount, _user);
        vm.startPrank(_user);
        THREE_POOL_TOKEN.approve(address(gVault), balance);
        shares = gVault.deposit(balance, _user);
        vm.stopPrank();
    }

    function prepareRewards(address _convexPool) public {
        uint256 slot = stdstore
            .target(_convexPool)
            .sig(IConvexRewards(_convexPool).rewardRate.selector)
            .find();
        vm.store(
            _convexPool,
            bytes32(slot),
            bytes32(50 * IConvexRewards(_convexPool).rewardRate())
        );
        vm.warp(IConvexRewards(_convexPool).periodFinish() - 100);
    }
}

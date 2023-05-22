// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;
import {ERC20} from "./solmate/src/tokens/ERC20.sol";
import {Owned} from "./solmate/src/auth/Owned.sol";
import "./interfaces/ICurveMeta.sol";
import "./interfaces/ICurve3Pool.sol";
import "./interfaces/IOusdVault.sol";
import "./solmate/src/utils/SafeTransferLib.sol";

contract OUSDArb is Owned {
    using SafeTransferLib for ERC20;
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event ArbPerformed(
        uint256 _initialAmount,
        uint256 _finalAmount,
        uint256 _slippageAmount
    );
    /*//////////////////////////////////////////////////////////////
                        CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    ERC20 internal constant CRV_3POOL_TOKEN =
        ERC20(address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490));

    ERC20 public constant DAI =
        ERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    ERC20 public constant USDC =
        ERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    ERC20 public constant USDT =
        ERC20(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    ERC20 public constant OUSD =
        ERC20(address(0x2A8e1E676Ec238d8A992307B495b45B3fEAa5e86));

    ICurveMeta public constant OUSD_META =
        ICurveMeta(address(0x87650D7bbfC3A9F10587d7778206671719d9910D));
    ICurve3Pool public constant THREE_POOL =
        ICurve3Pool(address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7));
    IOusdVault public constant OVAULT =
        IOusdVault(address(0xE75D77B1865Ae93c7eaa3040B038D7aA7BC02F70));

    int128 public constant THREE_CURVE_META_INDEX = 1;
    int128 public constant OUSD_META_INDEX = 0;

    constructor() Owned(msg.sender) {
        OUSD.approve(address(OUSD_META), type(uint256).max);
        // Approve all 3 tokens allowance to 3curve pool
        DAI.approve(address(THREE_POOL), type(uint256).max);
        USDC.approve(address(THREE_POOL), type(uint256).max);
        USDT.safeApprove(address(THREE_POOL), type(uint256).max);
    }

    /// @notice This function is used to perform the arb
    /// @param _amount The amount of 3CRV to perform the arb with
    function performArbWithTransfer(uint256 _amount) external onlyOwner {
        // First, transfer the 3CRV token to this contract
        require(
            CRV_3POOL_TOKEN.allowance(msg.sender, address(this)) >= _amount,
            "!allowance"
        );
        CRV_3POOL_TOKEN.transferFrom(msg.sender, address(this), _amount);
        // Then, perform the arb
        performArb(50);
    }

    /// @notice run this function if you already have 3CRV token in this contract
    function performArb(uint256 _slippageAmount)
        public
        onlyOwner
        returns (uint256, uint256)
    {
        uint256 threeCurveBal = CRV_3POOL_TOKEN.balanceOf(address(this));
        // Require 3 curve token balance non-zero:
        require(threeCurveBal > 0, "!3CRV");
        // Swap the 3CRV for OUSD
        OUSD_META.exchange(
            THREE_CURVE_META_INDEX,
            OUSD_META_INDEX,
            threeCurveBal,
            0
        );

        // Make sure we have non-zero OUSD balance
        require(OUSD.balanceOf(address(this)) >= 0, "!OUSD");

        // Redeem the OUSD for stablecoins:
        OVAULT.redeemAll(0);

        // Collect all balances of 3 tokens
        uint256 _daiBalance = DAI.balanceOf(address(this));
        uint256 _usdcBalance = USDC.balanceOf(address(this));
        uint256 _usdtBalance = USDT.balanceOf(address(this));
        // Make sure that we have non-zero balance
        require((_daiBalance + _usdcBalance + _usdtBalance) > 0, "!balance");

        uint256[3] memory _tokenAmounts = [
            _daiBalance,
            _usdcBalance,
            _usdtBalance
        ];

        // Deposit liquidity to 3 curve pool
        THREE_POOL.add_liquidity(_tokenAmounts, 0);

        // Check 3curve token amounts with slippage
        uint256 threeCurveAfter = CRV_3POOL_TOKEN.balanceOf(address(this));
        uint256 slippageAmount = (_slippageAmount * threeCurveBal) / 10000;
        require(threeCurveAfter > threeCurveBal - slippageAmount, "!slippage");
        emit ArbPerformed(threeCurveBal, threeCurveAfter, slippageAmount);

        return (threeCurveBal, threeCurveAfter);
    }

    /// @notice This function is used to sweep any tokens that are stuck in the contract
    function sweep(address asset) external onlyOwner {
        ERC20(asset).transfer(
            msg.sender,
            ERC20(asset).balanceOf(address(this))
        );
    }
}

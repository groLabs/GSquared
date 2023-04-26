// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.10;

library StrategyErrors {
    error NotOwner(); // 0x30cd7471
    error NotVault(); // 0x62df0545
    error NotKeeper(); // 0xf512b278
    error ConvexShutdown(); // 0xdbd83f91
    error RewardsTokenMax(); // 0x8f24ac29
    error Stopped(); // 0x7acc84e3
    error SamePid(); // 0x4eb5bc6d
    error BaseAsset(); // 0xaeca768b
    error LpToken(); // 0xaeca768b
    error ConvexToken(); // 0xaeca768b
    error LTMinAmountExpected(); // 0x3d93e699
    error ExcessDebtGtThanAssets(); // 0x961696d0
    error LPNotZero(); // 0xe4e07afa
    error SlippageProtection(); // 0x17d431f4
}

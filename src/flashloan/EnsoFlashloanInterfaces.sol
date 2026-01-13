// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

// interface IERC3156FlashBorrower {
//     function onFlashLoan(
//         address initiator,
//         address token,
//         uint256 amount,
//         uint256 fee,
//         bytes calldata data
//     )
//         external
//         returns (bytes32);
// }

interface IMorpho {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IAaveV3Pool {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    )
        external;
}

struct BalancerV3FlashloanParams {
    address wallet;
    address[] tokens;
    uint256[] amounts;
    bytes32 accountId;
    bytes32 requestId;
    bytes32[] commands;
    bytes[] state;
}

interface IBalancerV3Vault {
    function unlock(bytes calldata data) external;
    function sendTo(address token, address to, uint256) external;
    function settle(address token, uint256 amount) external;
}

// --- Dolomite Types and Interfaces ---

library DolomiteTypes {
    struct AccountInfo {
        address owner;
        uint256 number;
    }

    enum AssetDenomination {
        Wei,
        Par
    }

    enum AssetReference {
        Delta,
        Target
    }

    struct AssetAmount {
        bool sign; // true = positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }
}

library DolomiteActions {
    enum ActionType {
        Deposit,
        Withdraw,
        Transfer,
        Buy,
        Sell,
        Trade,
        Liquidate,
        Vaporize,
        Call
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        DolomiteTypes.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}

interface IDolomiteMargin {
    function operate(DolomiteTypes.AccountInfo[] memory accounts, DolomiteActions.ActionArgs[] memory actions) external;

    function getMarketIdByTokenAddress(address token) external view returns (uint256);
}

struct DolomiteFlashloanParams {
    address wallet;
    address token;
    uint256 amount;
    bytes32 accountId;
    bytes32 requestId;
    bytes32[] commands;
    bytes[] state;
}

// --- UniswapV3 Types and Interfaces ---

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function factory() external view returns (address);
    function fee() external view returns (uint24);
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

struct UniswapV3FlashloanParams {
    address wallet;
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
    bytes32 accountId;
    bytes32 requestId;
    bytes32[] commands;
    bytes[] state;
}


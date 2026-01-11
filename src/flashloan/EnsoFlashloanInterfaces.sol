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


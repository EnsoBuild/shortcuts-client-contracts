// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

interface IRouter {
    enum TokenType {
        Native,
        ERC20,
        ERC721,
        ERC1155
    }

    struct Token {
        TokenType tokenType;
        bytes data;
    }

    function routeSingle(
        Token calldata tokenIn,
        bytes calldata data
    ) external payable returns (bytes memory response);
}

interface IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

interface IMorpho {
    function flashLoan(
        address token,
        uint256 assets,
        bytes calldata data
    ) external;
}

interface IEVault {
    function flashLoan(uint256 amount, bytes calldata data) external;
}

interface IBalancerV2Vault {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IAaveV3Pool {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

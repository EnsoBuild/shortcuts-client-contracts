// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ShortcutDataTypes {
    enum RoutingStrategy {
        ENSOWALLET,
        ROUTER,
        DELEGATE,
        EIP7702,
        ROUTER_LEGACY,
        DELEGATE_LEGACY
    }

    struct Shortcut {
        RoutingStrategy routingStrategy;
        address from;
        address receiver;
        address spender;
        address[] tokensIn;
        uint256[] amountsIn;
        address[] tokensOut;
        uint256 slippage;
        uint256 fee;
        address feeReceiver;
        uint256 txGas;
        bytes txData;
        string referralCode;
    }
}

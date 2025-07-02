// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "./AbstractEnsoShortcuts.sol";

contract EnsoShortcuts is AbstractEnsoShortcuts {
    address public immutable executor;

    error NotPermitted();

    constructor(address executor_) {
        executor = executor_;
    }

    function _checkMsgSender() internal view override {
        if (msg.sender != executor) revert NotPermitted();
    }
}

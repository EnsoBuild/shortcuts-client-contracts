// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";

contract DelegateEnsoShortcuts is AbstractEnsoShortcuts {
    address private immutable __self = address(this);

    error OnlyDelegateCall();

    function _checkMsgSender() internal view override {
        if (address(this) == __self) revert OnlyDelegateCall();
    }
}

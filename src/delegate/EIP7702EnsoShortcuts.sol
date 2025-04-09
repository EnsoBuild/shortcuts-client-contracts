// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSendCall } from "../AbstractMultiSendCall.sol";

contract EIP7702EnsoShortcuts is AbstractMultiSendCall, AbstractEnsoShortcuts {
    /// @notice Thrown caller is not this address.
    error OnlySelfCall();

    /// @notice Function to validate msg.sender.
    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSendCall) {
        if (msg.sender != address(this)) revert OnlySelfCall();
    }
}

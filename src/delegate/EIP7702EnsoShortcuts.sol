// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";

contract EIP7702EnsoShortcuts is AbstractMultiSend, AbstractEnsoShortcuts {
    /// @notice Thrown caller is not this address.
    error OnlySelfCall();

    /// @notice Function to validate msg.sender.
    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        if (msg.sender != address(this)) revert OnlySelfCall();
    }
}

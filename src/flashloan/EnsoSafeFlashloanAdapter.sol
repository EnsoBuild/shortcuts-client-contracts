// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractEnsoFlashloan, LenderProtocol } from "./AbstractEnsoFlashloan.sol";
import { ISafe } from "safe-smart-account-1.5.0/interfaces/ISafe.sol";
import { Enum } from "safe-smart-account-1.5.0/libraries/Enum.sol";

contract EnsoSafeFlashloanAdapter is AbstractEnsoFlashloan {
    error SafeExecutionFailed();

    address public immutable shortcuts;

    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address shortcuts_,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    {
        shortcuts = shortcuts_;
    }

    function executeShortcut(
        address wallet,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] memory commands,
        bytes[] memory state
    )
        internal
        override
    {
        bytes memory data = abi.encodeCall(
            AbstractEnsoShortcuts.executeShortcut,
            (accountId, requestId, commands, state)
        );

        bool success = ISafe(payable(wallet)).execTransactionFromModule(
            shortcuts,
            0,
            data,
            Enum.Operation.DelegateCall
        );

        if (!success) revert SafeExecutionFailed();
    }
}

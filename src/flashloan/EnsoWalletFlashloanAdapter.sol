// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { AbstractEnsoFlashloan, LenderProtocol } from "./AbstractEnsoFlashloan.sol";

contract EnsoWalletFlashloanAdapter is AbstractEnsoFlashloan {
    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    { }

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
        IEnsoWalletV2(wallet).executeShortcut(accountId, requestId, commands, state);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { VM } from "enso-weiroll/VM.sol";

import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC721Holder } from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

abstract contract AbstractEnsoShortcuts is VM, ERC721Holder, ERC1155Holder {
    event ShortcutExecuted(bytes32 accountId, bytes32 requestId);

    // @notice Execute a shortcut
    // @param accountId The bytes32 value representing an API user
    // @param requestId The bytes32 value representing an API request
    // @param commands An array of bytes32 values that encode calls
    // @param state An array of bytes that are used to generate call data for each command
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        public
        payable
        virtual
        returns (bytes[] memory response)
    {
        _checkMsgSender();
        response = _execute(commands, state);
        emit ShortcutExecuted(accountId, requestId);
    }

    //@notice Abstract function to validate msg.sender
    function _checkMsgSender() internal view virtual;

    receive() external payable virtual { }
}

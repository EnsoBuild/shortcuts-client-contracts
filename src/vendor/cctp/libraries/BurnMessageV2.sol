/*
 * Copyright 2024 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * adapted from circle's BurnMessageV2 library for solidity 0.8 calldata.
 * source: https://github.com/circlefin/evm-cctp-contracts/blob/a92a2b4e7e6ef99bf0b05dca71780f5ec190e729/src/messages/v2/BurnMessageV2.sol
 */
pragma solidity ^0.8.28;

library BurnMessageV2 {
    uint256 private constant VERSION_INDEX = 0;
    uint256 private constant BURN_TOKEN_INDEX = 4;
    uint256 private constant MINT_RECIPIENT_INDEX = 36;
    uint256 private constant HOOK_DATA_INDEX = 228;

    error InvalidBurnMessageLength(uint256 length);

    function _getVersion(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, VERSION_INDEX);
    }

    function _getBurnToken(bytes calldata message) internal pure returns (bytes32) {
        return _readWord(message, BURN_TOKEN_INDEX);
    }

    function _getMintRecipient(bytes calldata message) internal pure returns (bytes32) {
        return _readWord(message, MINT_RECIPIENT_INDEX);
    }

    function _getHookData(bytes calldata message) internal pure returns (bytes calldata) {
        return message[HOOK_DATA_INDEX:];
    }

    function _validateBurnMessageFormat(bytes calldata message) internal pure {
        if (message.length < HOOK_DATA_INDEX) {
            revert InvalidBurnMessageLength(message.length);
        }
    }

    function _readUint32(bytes calldata data, uint256 index) private pure returns (uint32 value) {
        assembly ("memory-safe") {
            value := shr(224, calldataload(add(data.offset, index)))
        }
    }

    function _readWord(bytes calldata data, uint256 index) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            value := calldataload(add(data.offset, index))
        }
    }
}

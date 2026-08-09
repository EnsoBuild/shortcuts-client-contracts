/*
 * Copyright 2024 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * adapted from circle's MessageV2 library for solidity 0.8 calldata.
 * source: https://github.com/circlefin/evm-cctp-contracts/blob/a92a2b4e7e6ef99bf0b05dca71780f5ec190e729/src/messages/v2/MessageV2.sol
 */
pragma solidity ^0.8.28;

library MessageV2 {
    uint256 private constant VERSION_INDEX = 0;
    uint256 private constant SOURCE_DOMAIN_INDEX = 4;
    uint256 private constant NONCE_INDEX = 12;
    uint256 private constant RECIPIENT_INDEX = 76;
    uint256 private constant DESTINATION_CALLER_INDEX = 108;
    uint256 private constant MESSAGE_BODY_INDEX = 148;

    error InvalidMessageLength(uint256 length);

    function _getVersion(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, VERSION_INDEX);
    }

    function _getSourceDomain(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, SOURCE_DOMAIN_INDEX);
    }

    function _getNonce(bytes calldata message) internal pure returns (bytes32) {
        return _readWord(message, NONCE_INDEX);
    }

    function _getRecipient(bytes calldata message) internal pure returns (bytes32) {
        return _readWord(message, RECIPIENT_INDEX);
    }

    function _getDestinationCaller(bytes calldata message) internal pure returns (bytes32) {
        return _readWord(message, DESTINATION_CALLER_INDEX);
    }

    function _getMessageBody(bytes calldata message) internal pure returns (bytes calldata) {
        return message[MESSAGE_BODY_INDEX:];
    }

    function _validateMessageFormat(bytes calldata message) internal pure {
        if (message.length < MESSAGE_BODY_INDEX) {
            revert InvalidMessageLength(message.length);
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

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import { CCIPMessageDecoder } from "../../../../../src/libraries/CCIPMessageDecoder.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

contract CCIPMessageDecoder_TryDecodeMessageData_Unit_Concrete_Test is Test {
    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    // New head layout in memory (after the 32-byte length word):
    // [ receiver (32) | offset (32) ] -> 64 bytes
    uint256 private constant HEAD_SIZE = 64;

    function _encodeValid(address receiver, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encode(receiver, payload);
    }

    function _setOffset(bytes memory data, uint256 off) internal pure {
        // write at head[1] (offset word)
        assembly {
            mstore(add(data, add(32, 32)), off)
        }
    }

    function _peekOffsetMem(bytes memory data) internal pure returns (uint256 off) {
        assembly { off := mload(add(data, 64)) }
    }

    function _setTailLenAtOffset(bytes memory data, uint256 off, uint256 len) internal pure {
        // writes the tail length word at base+off
        // NOTE: caller must ensure base+off is within the allocated buffer
        assembly {
            mstore(add(add(data, 32), off), len)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS: < 96 bytes
    //////////////////////////////////////////////////////////////*/

    function test_WhenDataLengthLt96Bytes() external pure {
        // Arrange: make any buffer shorter than 96 bytes
        bytes memory data = new bytes(95);

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                        MOD: ≥ 96 bytes (valid base)
    //////////////////////////////////////////////////////////////*/

    modifier whenDataLengthGte96Bytes() {
        _;
    }

    function test_WhenOffsetIsNotWordAligned() external pure whenDataLengthGte96Bytes {
        // Arrange: abi.encode(address, bytes("")) → length = 96 (64 head + 32 length word)
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, bytes(""));
        // Make offset = 97 (not multiple of 32)
        _setOffset(msgData, 97);
        assertEq(_peekOffsetMem(msgData), 97, "offset mutation failed");

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                   MOD: offset is word-aligned (but not valid)
    //////////////////////////////////////////////////////////////*/

    modifier whenOffsetIsWordAligned() {
        _;
    }

    function test_WhenOffsetIsBefore2WordHead() external pure whenDataLengthGte96Bytes whenOffsetIsWordAligned {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, bytes(""));
        _setOffset(msgData, 32); // word-aligned but < 64 (invalid for our layout)
        assertEq(_peekOffsetMem(msgData), 32, "offset mutation failed");

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                 MOD: offset is after the 2-word head (≥ 64)
    //////////////////////////////////////////////////////////////*/

    modifier whenOffsetIsAfter2WordHead() {
        _;
    }

    function test_WhenThereIsNotEnoughRoomForTailLengthWord()
        external
        pure
        whenDataLengthGte96Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter2WordHead
    {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, bytes(""));
        // Start from valid base and set offset to the canonical value (64)
        _setOffset(msgData, HEAD_SIZE); // 64
        // Make offset so large that data.length < off + 32.
        // Current msgData.length == 96 and word-aligned, so set off = 96.
        _setOffset(msgData, msgData.length);

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
         MOD: enough room for tail length, but tail may/may not fit
    //////////////////////////////////////////////////////////////*/

    modifier whenThereIsEnoughRoomForTailLengthWord() {
        _;
    }

    function test_WhenTailDoesNotFullyFit()
        external
        pure
        whenDataLengthGte96Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter2WordHead
        whenThereIsEnoughRoomForTailLengthWord
    {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, bytes(""));
        // Set offset = 64 so the length word is within bounds (96 >= 64+32)
        _setOffset(msgData, HEAD_SIZE); // 64
        // With base length=96 and off=64, avail = 96 - (64+32) = 0
        // Writing len=1 makes it overflow the available tail → should fail
        _setTailLenAtOffset(msgData, HEAD_SIZE, 1);

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function test_WhenTailFullyFits()
        external
        pure
        whenDataLengthGte96Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter2WordHead
        whenThereIsEnoughRoomForTailLengthWord
    {
        // Arrange
        // Build a valid payload where tail fully fits: len=3 → ceil32=32
        // Total = 64 + 32 + 32 = 128 bytes
        bytes memory payload = hex"010203";
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, payload);

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(msgData);

        // Assert
        // it should return a successful result
        assertTrue(decodeSuccess);
        assertEq(receiver, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(shortcutData, payload);
        assertEq(msgData.length, 128);
    }
}

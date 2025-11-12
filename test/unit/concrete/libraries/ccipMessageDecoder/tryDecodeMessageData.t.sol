// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import { CCIPMessageDecoder } from "../../../../../src/libraries/CCIPMessageDecoder.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

contract CCIPMessageDecoder_TryDecodeMessageData_Unit_Concrete_Test is Test {
    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    // Head layout in memory (after the 32-byte length word):
    // [ receiver (32) | estimatedGas (32) | offset (32) ] -> 96 bytes
    uint256 private constant HEAD_SIZE = 96;

    function _encodeValid(
        address receiver,
        uint256 estimatedGas,
        bytes memory payload
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(receiver, estimatedGas, payload);
    }

    function _setOffset(bytes memory data, uint256 off) internal pure {
        // write at head[2] (offset word)
        assembly {
            mstore(add(data, add(32, 64)), off)
        }
    }

    function _peekOffsetMem(bytes memory data) internal pure returns (uint256 off) {
        assembly { off := mload(add(data, 96)) }
    }

    function _setTailLenAtOffset(bytes memory data, uint256 off, uint256 len) internal pure {
        // writes the tail length word at base+off
        // NOTE: caller must ensure base+off is within the allocated buffer
        assembly {
            mstore(add(add(data, 32), off), len)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS: < 128 bytes
    //////////////////////////////////////////////////////////////*/

    function test_WhenDataLengthLt128Bytes() external pure {
        // Arrange
        bytes memory data =
            hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                        MOD: ≥ 128 bytes (valid base)
    //////////////////////////////////////////////////////////////*/

    modifier whenDataLengthGte128Bytes() {
        _;
    }

    function test_WhenOffsetIsNotWordAligned() external pure whenDataLengthGte128Bytes {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 123, bytes(""));
        // Make offset = 97 (not multiple of 32)
        _setOffset(msgData, 97);
        assertEq(_peekOffsetMem(msgData), 97, "offset mutation failed");

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                   MOD: offset is word-aligned (but not valid)
    //////////////////////////////////////////////////////////////*/

    modifier whenOffsetIsWordAligned() {
        _;
    }

    function test_WhenOffsetIsBefore3WordHead() external pure whenDataLengthGte128Bytes whenOffsetIsWordAligned {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 123, bytes(""));
        _setOffset(msgData, 64); // word-aligned but < 96 (invalid for our layout)
        assertEq(_peekOffsetMem(msgData), 64, "offset mutation failed");

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    /*//////////////////////////////////////////////////////////////
                 MOD: offset is after the 3-word head (≥ 96)
    //////////////////////////////////////////////////////////////*/

    modifier whenOffsetIsAfter3WordHead() {
        _;
    }

    function test_WhenThereIsNotEnoughRoomForTailLengthWord()
        external
        pure
        whenDataLengthGte128Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter3WordHead
    {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 123, bytes(""));
        // Start from valid base and set offset to the canonical value (96)
        _setOffset(msgData, HEAD_SIZE); // 96
        // Make offset so large that data.length < off + 32.
        // Current s_messageData.length == 128 and word-aligned, so set off = 128.
        _setOffset(msgData, msgData.length);

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
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
        whenDataLengthGte128Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter3WordHead
        whenThereIsEnoughRoomForTailLengthWord
    {
        // Arrange
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 123, bytes(""));
        // Set offset = 96 so the length word is within bounds (128 >= 96+32)
        _setOffset(msgData, HEAD_SIZE); // 96
        // With base length=128 and off=96, writing len=64 requires:
        // off + 32 + ceil32(64) = 96 + 32 + 64 = 192 > 128  → should fail
        _setTailLenAtOffset(msgData, HEAD_SIZE, 64);

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(msgData);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function test_WhenTailFullyFits()
        external
        pure
        whenDataLengthGte128Bytes
        whenOffsetIsWordAligned
        whenOffsetIsAfter3WordHead
        whenThereIsEnoughRoomForTailLengthWord
    {
        // Arrange
        // Build a valid payload where tail fully fits: len=3 → ceil32=32
        // Total = 96 + 32 + 32 = 160 bytes
        bytes memory payload = hex"010203";
        bytes memory msgData = _encodeValid(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, type(uint256).max, payload);

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(msgData);

        // Assert
        // it should return a successful result
        assertTrue(decodeSuccess);
        assertEq(receiver, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        assertEq(estimatedGas, type(uint256).max);
        assertEq(shortcutData, payload);
        assertEq(msgData.length, 160);
    }
}

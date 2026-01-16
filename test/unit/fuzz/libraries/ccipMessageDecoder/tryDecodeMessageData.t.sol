// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import { CCIPMessageDecoder } from "../../../../../src/libraries/CCIPMessageDecoder.sol";
import { Test } from "forge-std/Test.sol";

contract CCIPMessageDecoder_TryDecodeMessageData_Unit_Fuzz_Test is Test {
    function testFuzz_unsuccessfulResult_lengthLt96Bytes(bytes memory _data) external pure {
        // Arrange
        vm.assume(_data.length < 96);

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(_data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessfulResult_misalignedOffset(
        address _receiver,
        bytes memory _tail,
        uint8 _wiggle
    )
        external
        pure
    {
        // Arrange
        // Build a valid payload first
        bytes memory data = abi.encode(_receiver, _tail);

        // Choose an offset ≥64 but misaligned: 64 + [1..31]
        uint256 off = 64 + (uint256(_wiggle) % 31 + 1);

        // Overwrite offset at head[1] (base+32 => absolute +64 from bytes start)
        assembly { mstore(add(data, 64), off) }

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_offsetBeforeHead(address _receiver, bytes memory _tail, uint8 _k) external pure {
        // Arrange
        bytes memory data = abi.encode(_receiver, _tail);

        // Pick aligned off ∈ {0,32} (both < 64 → before 2-word head)
        uint256 aligned = (uint256(_k) % 2) * 32;
        assembly { mstore(add(data, 64), aligned) }

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_offsetBeyondEnd(address _receiver, bytes memory _tail) external pure {
        // Arrange
        bytes memory data = abi.encode(_receiver, _tail);

        // Set off = data.length (aligned since abi.encode pads to /32)
        uint256 off = data.length;
        assembly { mstore(add(data, 64), off) }

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_tailDoesNotFit(address _receiver) external pure {
        // Arrange
        // Start with empty tail → total 96 bytes (64 head + 32 length word)
        bytes memory data = abi.encode(_receiver, bytes(""));
        // off = 64 (canonical)
        assembly { mstore(add(data, 64), 64) }
        // Write len=1 → requires 64 + 32 + ceil32(1)=64+32+32=128 bytes total,
        // but current buffer is only 96 → should fail
        assembly { mstore(add(data, 96), 1) }

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_hugeLenOverflowGuard(address _receiver) external pure {
        // Arrange
        // Empty tail → total 96 bytes; off = 64
        bytes memory data = abi.encode(_receiver, bytes(""));
        assembly { mstore(add(data, 64), 64) }
        // len = max => ceil32(len) definitely exceeds remaining buffer
        assembly { mstore(add(data, 96), not(0)) }

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_success_receiverMasking(bytes20 _low20, bytes12 _garbageHigh) external pure {
        // Arrange
        address expectedReceiver = address(uint160(uint256(bytes32(_low20))));
        // Build a valid encoding with zeroed head, empty tail
        bytes memory data = abi.encode(address(0), bytes(""));
        // Overwrite receiver head word with high-12 garbage | low-20 address
        bytes32 word = bytes32(_garbageHigh) | bytes32(_low20);
        assembly { mstore(add(data, 32), word) }

        // Act
        (bool decodeSuccess, address receiver,) = CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        assertTrue(decodeSuccess);
        assertEq(receiver, expectedReceiver);
    }

    function testFuzz_unsuccessful_superfluousTrailingBytes(
        address _receiver,
        bytes memory _shortcutData,
        uint8 _extraBytes
    )
        external
        pure
    {
        // Arrange
        // Ensure at least 1 extra byte (1-32 range from uint8, avoiding 0)
        uint256 extra = uint256(_extraBytes) % 32 + 1;

        // Build valid encoding, then append extra bytes
        bytes memory validData = abi.encode(_receiver, _shortcutData);
        bytes memory data = abi.encodePacked(validData, new bytes(extra));

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return an unsuccessful result due to superfluous bytes
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(shortcutData, "");
    }

    function testFuzz_successfulResult(address _receiver, bytes memory _shortcutData) external pure {
        // Arrange
        bytes memory data = abi.encode(_receiver, _shortcutData);

        (address decodedReceiver, bytes memory decodedShortcutData) = abi.decode(data, (address, bytes));

        // Act
        (bool decodeSuccess, address receiver, bytes memory shortcutData) =
            CCIPMessageDecoder._tryDecodeMessageData(data);

        // Assert
        // it should return a successful result
        assertTrue(decodeSuccess);
        assertEq(receiver, _receiver);
        assertEq(shortcutData, _shortcutData);

        // Differential
        assertEq(receiver, decodedReceiver);
        assertEq(shortcutData, decodedShortcutData);
    }
}

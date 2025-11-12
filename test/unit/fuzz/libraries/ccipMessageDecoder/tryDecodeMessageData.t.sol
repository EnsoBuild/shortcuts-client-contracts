// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import { CCIPMessageDecoder } from "../../../../../src/libraries/CCIPMessageDecoder.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

contract CCIPMessageDecoder_TryDecodeMessageData_Unit_Fuzz_Test is Test {
    function testFuzz_unsuccessfulResult_lengthLt128Bytes(bytes memory _data) external pure {
        // Arrange
        vm.assume(_data.length < 128);

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(_data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessfulResult_misalignedOffset(
        address _receiver,
        uint256 _estimatedGas,
        bytes memory _tail,
        uint8 _wiggle
    )
        external
        pure
    {
        // Arrange
        // Build a valid payload first
        bytes memory data = abi.encode(_receiver, _estimatedGas, _tail);

        // Choose an offset ≥96 but misaligned: 96 + [1..31]
        uint256 off = 96 + (uint256(_wiggle) % 31 + 1);

        // Overwrite offset at head[2]
        assembly { mstore(add(data, 96), off) }

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_offsetBeforeHead(
        address _receiver,
        uint256 _estimatedGas,
        bytes memory _tail,
        uint8 _k
    )
        external
        pure
    {
        // Arrange
        bytes memory data = abi.encode(_receiver, _estimatedGas, _tail);

        // Pick aligned off ∈ {0,32,64}
        uint256 aligned = (uint256(_k) % 3) * 32;
        assembly { mstore(add(data, 96), aligned) }

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_offsetBeyondEnd(
        address _receiver,
        uint256 _estimatedGas,
        bytes memory _tail
    )
        external
        pure
    {
        // Arrange
        bytes memory data = abi.encode(_receiver, _estimatedGas, _tail);

        // Set off = data.length (aligned since abi.encode makes length % 32 == 0 when tail present/empty)
        uint256 off = data.length;
        assembly { mstore(add(data, 96), off) }

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_tailDoesNotFit(address _receiver, uint256 _estimatedGas) external pure {
        // Arrange
        // Start with empty tail → total 128 bytes
        bytes memory data = abi.encode(_receiver, _estimatedGas, bytes(""));
        // off=96 (canonical)
        assembly { mstore(add(data, 96), 96) }
        // Write len=64 → requires 96 + 32 + 64 = 192 > 128
        assembly { mstore(add(data, 128), 64) }

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_unsuccessful_hugeLenOverflowGuard(address _receiver, uint256 _estimatedGas) external pure {
        // Start with empty tail → total 128 bytes
        bytes memory data = abi.encode(_receiver, _estimatedGas, bytes(""));
        // off = 96
        assembly { mstore(add(data, 96), 96) }
        // len = max => ceil32(len) definitely exceeds remaining buffer
        assembly { mstore(add(data, 128), not(0)) }

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a unsuccessful result
        assertFalse(decodeSuccess);
        assertEq(receiver, address(0));
        assertEq(estimatedGas, 0);
        assertEq(shortcutData, "");
    }

    function testFuzz_success_receiverMasking(bytes20 _low20, bytes12 _garbageHigh) external pure {
        // Arrange
        address expectedReceiver = address(uint160(uint256(bytes32(_low20))));
        // Build a valid encoding
        bytes memory data = abi.encode(address(0), uint256(0), bytes(""));
        // Overwrite receiver head word with high-12 garbage | low-20 address
        bytes32 word = bytes32(_garbageHigh) | bytes32(_low20);
        assembly { mstore(add(data, 32), word) }

        // Act
        (bool decodeSuccess, address receiver,,) = CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        assertTrue(decodeSuccess);
        assertEq(receiver, expectedReceiver);
    }

    function testFuzz_successfulResult(
        address _receiver,
        uint256 _estimatedGas,
        bytes memory _shortcutData
    )
        external
        pure
    {
        // Arrange
        bytes memory data = abi.encode(_receiver, _estimatedGas, _shortcutData);

        (address decodedReceiver, uint256 decodedEstimatedGas, bytes memory decodedShortcutData) =
            abi.decode(data, (address, uint256, bytes));

        // Act
        (bool decodeSuccess, address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            CCIPMessageDecoder.tryDecodeMessageData(data);

        // Assert
        // it should return a successful result
        assertTrue(decodeSuccess);
        assertEq(receiver, _receiver);
        assertEq(estimatedGas, _estimatedGas);
        assertEq(shortcutData, _shortcutData);

        // Differential
        assertEq(receiver, decodedReceiver);
        assertEq(estimatedGas, decodedEstimatedGas);
        assertEq(shortcutData, decodedShortcutData);
    }
}

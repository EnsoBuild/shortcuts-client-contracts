// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

library CCIPMessageDecoder {
    /// @dev Safe, non-reverting decoder for abi.encode(address,uint256,bytes) in MEMORY.
    ///      Returns (ok, receiver, estimatedGas, shortcutData). On malformed input, ok=false.
    ///      Layout: HEAD (96 bytes) = [receiver|estimatedGas|offset], TAIL at (base+off) = [len|bytes...].
    function tryDecodeMessageData(bytes memory _data)
        internal
        pure
        returns (bool success, address receiver, uint256 estimatedGas, bytes memory shortcutData)
    {
        // Need 3 head words (96) + 1 length word (32)
        if (_data.length < 128) {
            return (false, address(0), 0, bytes(""));
        }

        // Pointer to first head word
        uint256 base;
        assembly { base := add(_data, 32) }

        uint256 off;
        assembly ("memory-safe") {
            // Address is right-aligned in the word → keep low 20 bytes
            receiver := and(mload(base), 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            estimatedGas := mload(add(base, 32))
            off := mload(add(base, 64))
        }

        // Word-aligned offset?
        if ((off & 31) != 0) {
            return (false, address(0), 0, bytes(""));
        }

        uint256 baseLen = _data.length;

        // Off must be at/after 3-word head and leave room for tail length word
        // i.e.  off >= 96  &&  off <= baseLen - 32  (avoid off+32 overflow)
        if (off < 96 || off > baseLen - 32) {
            return (false, address(0), 0, bytes(""));
        }

        // Safe now to compute tail start (no overflow)
        uint256 tailStart = off + 32;

        // Read tail len
        uint256 len;
        assembly ("memory-safe") {
            len := mload(add(base, off))
        }

        unchecked {
            // Available bytes remaining after the tail length word
            uint256 avail = baseLen - tailStart;

            // Require len itself to fit in the available tail
            if (len > avail) {
                return (false, address(0), 0, bytes(""));
            }

            // Ceil32(len) and ensure padded bytes also fit (defensive; usually implied by len<=avail)
            uint256 padded = (len + 31) & ~uint256(31);
            if (padded > avail) {
                return (false, address(0), 0, bytes(""));
            }

            // Allocate and copy exactly `len` bytes (ignore padding)
            shortcutData = new bytes(len);
            if (len != 0) {
                assembly ("memory-safe") {
                    let src := add(add(base, off), 32) // start of tail payload
                    let dst := add(shortcutData, 32) // start of new bytes payload
                        // Copy in 32-byte chunks up to padded boundary
                    for { let i := 0 } lt(i, padded) { i := add(i, 32) } {
                        mstore(add(dst, i), mload(add(src, i)))
                    }
                }
            }
        }

        return (true, receiver, estimatedGas, shortcutData);
    }
}

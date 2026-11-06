// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Lifetime } from "../interfaces/IIntent.sol";

/// @title IntentRecord
/// @notice Execution records for intent lifetimes: one packed word, `window | count << 64`, where
///         `window` is the last window used plus one (0 = never executed). A window of
///         type(uint64).max is terminal: the intent is cancelled.
library IntentRecord {
    uint8 internal constant ALLOWED = 0;
    uint8 internal constant WAIT = 1; // the current window is already used
    uint8 internal constant EXHAUSTED = 2; // used, out of executions, or cancelled

    uint256 internal constant CANCELLED = type(uint64).max;

    /// @notice Whether a lifetime needs a record at all. Unscheduled, uncounted standing intents
    ///         (deposit addresses) execute on every deposit and keep none.
    function needed(Lifetime memory lifetime) internal pure returns (bool) {
        return lifetime.kind == Codes.ONCE || lifetime.interval > 0 || lifetime.count > 0;
    }

    /// @notice The verdict for executing now, and the record to store if it executes.
    function next(
        Lifetime memory lifetime,
        uint64 start,
        uint256 record
    )
        internal
        view
        returns (uint8 verdict, uint256 updated)
    {
        uint64 window = uint64(record);
        uint32 count = uint32(record >> 64);
        // The terminal check comes first: an unscheduled, uncounted lifetime reads neither field.
        if (window == type(uint64).max) {
            return (EXHAUSTED, record);
        }
        if (lifetime.kind == Codes.ONCE) {
            return count > 0 ? (EXHAUSTED, record) : (ALLOWED, _pack(1, 1));
        }
        if (lifetime.count > 0 && count >= lifetime.count) {
            return (EXHAUSTED, record);
        }
        if (lifetime.interval > 0) {
            // Windows are anchored at start, never at the previous execution, so a late execution
            // doesn't push later windows back and the keeper can't choose when one opens.
            // forge-lint: disable-next-line(block-timestamp)
            uint64 current = uint64((block.timestamp - start) / lifetime.interval) + 1;
            if (window >= current) {
                return (WAIT, record);
            }
            window = current;
        }
        return (ALLOWED, _pack(window, count + 1));
    }

    function _pack(uint64 window, uint32 count) private pure returns (uint256) {
        return uint256(window) | (uint256(count) << 64);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// Usage is recorded per writer: each caller can only ever write its own entries, so an intent's
/// executor (or the router, for signed intents) needs no further authentication.
interface IIntentCounter {
    error CapExceeded(uint256 used, uint256 cap);

    /// @notice Add `amount` to the caller's usage for (intent, key) in the current window.
    /// @param period Window length in seconds; 0 = one window for the intent's life
    /// @return used Usage in the window, including `amount`
    function consume(
        bytes32 intent,
        bytes32 key,
        uint256 amount,
        uint256 cap,
        uint64 period
    )
        external
        returns (uint256 used);

    function used(address writer, bytes32 intent, bytes32 key, uint64 period) external view returns (uint256);
}

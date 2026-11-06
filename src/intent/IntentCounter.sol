// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IIntentCounter } from "../interfaces/IIntentCounter.sol";

/// @title IntentCounter
/// @notice Per-writer usage counters for intents. Entries are keyed by msg.sender, so no caller can
///         touch another's usage: an ephemeral executor's address is unique to its intent tree, and
///         a router keys its entries by the signed intent's hash.
contract IntentCounter is IIntentCounter {
    mapping(address writer => mapping(bytes32 slot => uint256 usage)) private s_used;

    function consume(
        bytes32 intent,
        bytes32 key,
        uint256 amount,
        uint256 cap,
        uint64 period
    )
        external
        returns (uint256 used_)
    {
        bytes32 slot = _slot(intent, key, period);
        used_ = s_used[msg.sender][slot] + amount;
        if (used_ > cap) {
            revert CapExceeded(used_, cap);
        }
        s_used[msg.sender][slot] = used_;
    }

    function used(address writer, bytes32 intent, bytes32 key, uint64 period) external view returns (uint256) {
        return s_used[writer][_slot(intent, key, period)];
    }

    function _slot(bytes32 intent, bytes32 key, uint64 period) private view returns (bytes32) {
        // forge-lint: disable-next-line(block-timestamp)
        uint256 window = period == 0 ? 0 : block.timestamp / period;
        return keccak256(abi.encode(intent, key, period, window));
    }
}

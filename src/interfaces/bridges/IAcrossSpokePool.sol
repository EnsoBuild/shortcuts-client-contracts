// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// Across SpokePool, as published in the across-protocol contracts package 4.x: the deposit entry
/// point BridgeGuardian uses.
interface IAcrossSpokePool {
    /// Pulls `inputAmount` of `inputToken` from msg.sender. `quoteTimestamp` must be within
    /// depositQuoteTimeBuffer of now and `fillDeadline` within fillDeadlineBuffer. An unfilled
    /// deposit is refunded to `depositor` on this chain after `fillDeadline`.
    function deposit(
        bytes32 depositor,
        bytes32 recipient,
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        bytes32 exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter,
        bytes calldata message
    )
        external
        payable;
}

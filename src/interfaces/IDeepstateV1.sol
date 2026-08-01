// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Deepstate V1 interface
/// @notice Minimal interface required to execute a netted sequence of order-book fills.
interface IDeepstateV1 {
    /// @notice One sequential route leg.
    /// @param token0 Lower-addressed asset in the book pair. Native ETH is `address(0)`.
    /// @param token1 Higher-addressed asset in the book pair.
    /// @param epoch Book epoch selected for matching.
    /// @param order Packed Deepstate order containing tick, quantity, correction, and nonce fields.
    /// @param isBid Whether the incoming order buys token0 with token1.
    /// @param noRest Whether unmatched quantity must be returned instead of resting on the book.
    /// @param fillOrKill Whether the leg must fill its entire incoming quantity.
    struct FillParams {
        address token0;
        address token1;
        uint256 epoch;
        bytes32 order;
        bool isBid;
        bool noRest;
        bool fillOrKill;
    }

    /// @notice Executes route legs sequentially and settles their net token deltas with the caller.
    function fillRoute(FillParams[] calldata fills) external payable;
}

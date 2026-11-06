// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Token } from "./IEnsoRouter.sol";

/// A delivery obligation, built from a Handoff at execution.
struct Obligation {
    uint256 chainId;
    bytes32 method; // 0 = any method the guardian supports
    address recipient;
    address refund; // refunds the method itself makes
    address token;
    uint256 minAmount;
    uint64 deadline;
}

enum Level {
    FORWARD,
    BONDED,
    FRONTED
}

enum Status {
    NONE,
    PENDING,
    FULFILLED,
    FAILED
}

interface IIntentGuardian {
    event Accepted(bytes32 indexed receipt, bytes32 indexed intentHash, address keeper, Obligation obligation);
    event Settled(bytes32 indexed receipt, Status outcome);

    function level() external view returns (Level);

    /// @notice Take `amount` of `token` from the caller against `obligation`. Native arrives as call
    ///         value, which may also carry the method's messaging fee.
    /// @param context Keeper-supplied: method parameters, never anything that redirects value
    function accept(
        bytes32 intentHash,
        Token calldata token,
        uint256 amount,
        Obligation calldata obligation,
        bytes calldata context
    )
        external
        payable
        returns (bytes32 receipt);

    function settle(bytes32 receipt, Status outcome, bytes calldata proof) external;

    function status(bytes32 receipt) external view returns (Status);
}

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
    /// `caller` is the account that called `accept` and handed `amount`. Anyone may call `accept`:
    /// a record counts only when `caller` is the intent address or the router of `intentHash`.
    event Accepted(
        bytes32 indexed receipt,
        bytes32 indexed intentHash,
        address indexed caller,
        address owner,
        address keeper,
        uint256 amount,
        Obligation obligation
    );
    event Settled(bytes32 indexed receipt, Status outcome);

    function level() external view returns (Level);

    /// @notice Take `amount` of `token` from the caller against `obligation`. Native arrives as call
    ///         value: a native input's amount, plus the keeper's messaging fee for this handoff.
    ///         Fee value the method doesn't use, and any refund of it the method makes later, goes
    ///         to `keeper`, never to the caller: the caller may be an intent address, whose native
    ///         is the owner's.
    /// @param owner The intent's owner. Signed for only when the caller is the IntentRouter: an
    ///        intent address's owner is a field of a leaf anyone can build. A guardian that acts on
    ///        the owner's account accepts calls from the IntentRouter alone.
    /// @param keeper The executing keeper, who paid the messaging fee
    /// @param context Keeper-supplied. Its first word is the messaging fee forwarded with this call
    ///        (the evaluator reads it; an empty context forwards none); the rest is the guardian's
    ///        own method parameters, never anything that redirects the handed amount
    function accept(
        bytes32 intentHash,
        address owner,
        address keeper,
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

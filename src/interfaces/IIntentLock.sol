// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// The intent lock: one intent executes at a time in a transaction, through the EphemeralFactory or
/// the IntentRouter. Outcome bounds measure an account's change over the whole execution, so an
/// intent run inside another's route would have its payout counted by both: one payment would
/// satisfy two intents, and the keeper would keep an input. A lock per contract would still let a
/// route on one carrier run an intent on the other, so both share this one, held by the factory.
interface IIntentLock {
    /// An intent is already executing in this transaction.
    error Locked();

    /// @notice Take the lock for the rest of the caller's run. Permissionless: a lock taken in a
    ///         transaction blocks only that transaction.
    function enter() external;

    /// @notice Release the lock, when the caller holds it.
    function exit() external;
}

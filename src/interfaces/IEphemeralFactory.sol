// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Token } from "./IEnsoRouter.sol";
import { Intent, Lifetime } from "./IIntent.sol";

/// What a caller supplies to run one leaf of an intent tree. Never part of the address.
struct Execution {
    Intent intent; // this chain's leaf, or the default leaf
    bytes32[] proof; // Merkle proof of the leaf against the root
    address router; // used only when the leaf's constraints name no router
    bytes[] routes; // keeper bytes per rule; the owner route arm runs routes[0]
    bytes[] contexts; // guardian context per handoff
    Token[] sweep; // extra assets for the refund arms, and non-inputs to return after execution
}

interface IEphemeralFactory {
    /// The executed leaf is in the transaction's calldata; the event carries the identifiers only.
    event Executed(address indexed executor, bytes32 indexed root);

    function executeIntent(bytes32 root, Execution calldata execution) external returns (address executor);

    function getAddress(bytes32 root) external view returns (address);

    /// @return execution abi.encode(Execution) of the call being executed
    function context() external view returns (bytes memory execution, address sender, bytes32 domain);

    function record(Lifetime calldata lifetime, uint64 start) external returns (uint8 verdict);

    function verdict(address executor, Lifetime calldata lifetime, uint64 start) external view returns (uint8);
}

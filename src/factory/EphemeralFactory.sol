// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { Execution, IEphemeralFactory } from "../interfaces/IEphemeralFactory.sol";
import { Lifetime } from "../interfaces/IIntent.sol";
import { IntentRecord } from "../libraries/IntentRecord.sol";
import { EphemeralIntentExecutor } from "../wallet/EphemeralIntentExecutor.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import { EIP712 } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";

/// @title EphemeralFactory
/// @notice Deploys and runs ephemeral intent executors at addresses derived from a Merkle root of
///         per-chain intents. No constructor arguments, so a salted CREATE2 deployment, and every
///         intent address, is the same on every chain. Its only immutables are EIP-712's cached
///         domain, derived from the deployment itself.
contract EphemeralFactory is IEphemeralFactory, EIP712, ReentrancyGuardTransient {
    error NonCanonicalEncoding();

    // Transient context for the executor's constructor (EIP-1153, cleared at end of transaction).
    // Solidity has no `transient bytes`, so abi.encode(execution) is chunked manually:
    // SENDER_SLOT holds the caller, CONTEXT_SLOT holds the length, data words follow it.
    uint256 private constant SENDER_SLOT = 0;
    uint256 private constant CONTEXT_SLOT = 1;

    /// @notice Execution records per executor. An executor's address is unique to its root, and
    ///         only that executor can write its own entry, so no other authorization is needed.
    mapping(address executor => uint256 record) public records;

    constructor() EIP712("EphemeralFactory", "2") { }

    /// @notice Deploy and run the executor for `root` with one of its leaves. Permissionless: a wrong
    ///         root derives an unfunded address, so the derivation authorizes. Not reentrant: a route
    ///         may not execute another intent mid-flight.
    function executeIntent(bytes32 root, Execution calldata execution)
        external
        nonReentrant
        returns (address executor)
    {
        // The executor decodes the execution itself; the factory passes its calldata through as the
        // abi.encode(execution) the executor expects, so it carries no codec for the nested types.
        (execution);
        if (uint256(bytes32(msg.data[36:68])) != 0x40) {
            revert NonCanonicalEncoding();
        }
        _setContext(bytes.concat(bytes32(uint256(0x20)), msg.data[68:]), msg.sender);
        // One copy of the executor's creation code serves both deployment and getAddress; `new`
        // would embed a second.
        bytes memory initCode = _initCode(root);
        assembly ("memory-safe") {
            executor := create2(0, add(initCode, 0x20), mload(initCode), 0)
        }
        if (executor == address(0)) {
            // Bubble the constructor's revert reason.
            assembly ("memory-safe") {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        // forge-lint: disable-next-line(reentrancy-events)
        emit Executed(executor, root);
    }

    /// @notice Address at which the intent tree with `root` executes.
    function getAddress(bytes32 root) public view returns (address) {
        bytes32 initCodeHash = keccak256(_initCode(root));
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(0), initCodeHash))))
            );
    }

    /// @notice Read by the executor's constructor: abi.encode(execution), the caller, and the domain
    ///         separator the executor's intent hash is computed under.
    function context() external view returns (bytes memory data, address sender, bytes32 domain) {
        assembly ("memory-safe") {
            sender := tload(SENDER_SLOT)
            let len := tload(CONTEXT_SLOT)
            data := mload(0x40)
            mstore(data, len)
            let words := shr(5, add(len, 31))
            let ptr := add(data, 0x20)
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                mstore(add(ptr, shl(5, i)), tload(add(add(CONTEXT_SLOT, 1), i)))
            }
            mstore(0x40, add(ptr, shl(5, words)))
        }
        domain = _domainSeparatorV4();
    }

    /// @notice Check and write the calling executor's record for one execution.
    function record(Lifetime calldata lifetime, uint64 start) external returns (uint8 verdict_) {
        uint256 updated;
        (verdict_, updated) = IntentRecord.next(lifetime, start, records[msg.sender]);
        if (verdict_ == IntentRecord.ALLOWED) {
            records[msg.sender] = updated;
        }
    }

    /// @notice What `record` would return for `executor`, without writing.
    function verdict(address executor, Lifetime calldata lifetime, uint64 start)
        external
        view
        returns (uint8 verdict_)
    {
        (verdict_,) = IntentRecord.next(lifetime, start, records[executor]);
    }

    function _initCode(bytes32 root) private pure returns (bytes memory) {
        return abi.encodePacked(type(EphemeralIntentExecutor).creationCode, abi.encode(root));
    }

    function _setContext(bytes memory data, address sender) private {
        assembly ("memory-safe") {
            tstore(SENDER_SLOT, sender)
            let len := mload(data)
            tstore(CONTEXT_SLOT, len)
            let words := shr(5, add(len, 31))
            let ptr := add(data, 0x20)
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                tstore(add(add(CONTEXT_SLOT, 1), i), mload(add(ptr, shl(5, i))))
            }
        }
    }
}

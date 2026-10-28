// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { Token } from "../interfaces/IEnsoRouter.sol";
import { Intent } from "../interfaces/IIntent.sol";
import { EphemeralIntentExecutor } from "../wallet/EphemeralIntentExecutor.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

contract EphemeralFactory is ReentrancyGuardTransient {
    // Transient context for the executor's constructor (EIP-1153, cleared at end of tx).
    // Solidity has no `transient bytes`, so abi.encode(route, sweep) is chunked manually:
    // SENDER_SLOT holds the caller, CONTEXT_SLOT holds the length, data words follow it.
    uint256 private constant SENDER_SLOT = 0;
    uint256 private constant CONTEXT_SLOT = 1;

    /// The execution layer — the executor's only call target. Immutable, so it joins the
    /// factory's initcode: same-address recovery requires the router at one address on
    /// every chain, exactly like the factory itself.
    address public immutable router;

    event IntentPublished(address indexed intentAddress, bytes intent);

    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address router_) {
        router = router_;
    }

    /// @notice Deploy and run `intent`'s executor at its derived address. Permissionless:
    ///         wrong parameters derive an unfunded address, so the derivation authorizes.
    ///         Not reentrant: a route may not execute another intent mid-flight, so one
    ///         intent's delivery can never be counted toward another's floor.
    /// @param route Shortcut data the router forwards to EnsoShortcuts when the intent
    ///              commits none, or the owner's own route. The caller chooses bytes,
    ///              never a target or function.
    /// @param sweep Extra assets (any Token type) for the refund arms to sweep. Like
    ///              `route`, never part of the address.
    function executeIntent(
        Intent calldata intent,
        bytes calldata route,
        Token[] calldata sweep
    )
        external
        nonReentrant
        returns (address executor)
    {
        _setContext(abi.encode(route, sweep), msg.sender);
        executor = address(new EphemeralIntentExecutor{ salt: bytes32(0) }(intent));
        // forge-lint: disable-next-line(reentrancy-events)
        emit IntentPublished(executor, abi.encode(intent));
    }

    /// @notice Address at which `intent` executes; abi.encode(intent) is the canonical blob.
    function getAddress(Intent calldata intent) public view returns (address) {
        // The creation-code prefix is fixed; the suffix is ABI-encoded constructor data.
        // forge-lint: disable-next-line(encode-packed-collision)
        return _predict(keccak256(abi.encodePacked(type(EphemeralIntentExecutor).creationCode, abi.encode(intent))));
    }

    /// @notice Read by the executor's constructor.
    function context() external view returns (bytes memory route, Token[] memory sweep, address sender, address) {
        bytes memory data;
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
        (route, sweep) = abi.decode(data, (bytes, Token[]));
        return (route, sweep, sender, router);
    }

    /// @notice Canonical executor creation code
    function executorCode() external pure returns (bytes memory) {
        return type(EphemeralIntentExecutor).creationCode;
    }

    function _predict(bytes32 initCodeHash) private view returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(0), initCodeHash))))
            );
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

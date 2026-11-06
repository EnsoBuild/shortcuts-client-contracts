// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Intent, Lifetime } from "../interfaces/IIntent.sol";
import { IIntentRouter } from "../interfaces/IIntentRouter.sol";
import { IntentEvaluator, Run } from "../libraries/IntentEvaluator.sol";
import { IntentHash } from "../libraries/IntentHash.sol";
import { IntentRecord } from "../libraries/IntentRecord.sol";
import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

/// @title IntentRouter
/// @notice Executes EIP-712 signed version 2 intents. Users approve this contract; the intent's
///         keeper submits it with its route bytes; tokens only ever move from the intent's owner,
///         and only as the signed constraints allow.
contract IntentRouter is IIntentRouter, EIP712, ReentrancyGuardTransient, ERC1155Holder {
    /// @notice Execution records per (owner, nonce): see IntentRecord. Intents an owner signs with
    ///         the same nonce share a record, and so form a cancellation group.
    mapping(address owner => mapping(uint256 nonce => uint256 record)) public records;

    error NotKeeper();
    error WrongChain();
    error TooEarly();
    error Expired();
    error InvalidSignature();
    error Rejected(uint8 status);
    error Exhausted();
    error NotYet();

    constructor() EIP712("IntentRouter", "2") { }

    /// @inheritdoc IIntentRouter
    function executeIntent(
        Intent calldata intent,
        bytes calldata signature,
        address router,
        bytes[] calldata routes,
        bytes[] calldata contexts
    )
        external
        payable
        nonReentrant
    {
        // forge-lint: disable-next-item(block-timestamp)
        if (
            intent.keeper != address(0) && msg.sender != intent.keeper
                && (intent.exclusive == 0 || block.timestamp < intent.exclusive)
        ) {
            revert NotKeeper();
        }
        // A default leaf (chain 0) exists only inside an ephemeral tree.
        if (intent.chainId != block.chainid) {
            revert WrongChain();
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (block.timestamp < intent.start) {
            revert TooEarly();
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (block.timestamp > intent.deadline) {
            revert Expired();
        }
        Intent memory signed = intent;
        bytes32 digest = _hashTypedDataV4(IntentHash.hash(signed));
        if (!_isValidSignature(intent.owner, digest, signature)) {
            revert InvalidSignature();
        }
        // A standing intent pulling from a wallet needs a schedule or a count: otherwise a keeper
        // could repeat it within one block until the owner's allowance runs out.
        Lifetime memory lifetime = signed.constraints.lifetime;
        if (
            lifetime.kind == Codes.STANDING && lifetime.interval == 0 && lifetime.count == 0
                && signed.constraints.inputs.assets.length > 0
        ) {
            revert Rejected(IntentEvaluator.MALFORMED);
        }
        // Written first; any revert below undoes it.
        _useRecord(signed);

        Run memory run = Run({
            id: digest,
            record: digest,
            holder: intent.owner,
            owner: intent.owner,
            pull: true,
            caller: msg.sender,
            records: address(0),
            router: router,
            routes: routes,
            contexts: contexts
        });
        // Attestation, trace patterns, malformed structure and unchecked keeper routes revert.
        uint8 status = IntentEvaluator.evaluate(signed, run);
        if (status != IntentEvaluator.OK) {
            revert Rejected(status);
        }
        // Messaging-fee native the guardians didn't need goes back to the keeper who sent it; the
        // router holds nothing between transactions.
        if (address(this).balance > 0) {
            // forge-lint: disable-next-line(arbitrary-send-eth)
            (bool ok,) = msg.sender.call{ value: address(this).balance }("");
            (ok);
        }
        // forge-lint: disable-next-line(reentrancy-events)
        emit IntentExecuted(intent.owner, intent.nonce, digest);
    }

    /// @notice Retire the caller's nonces, so no intent carrying them can execute again, standing or
    ///         not. A nonce never used is retired before its first execution.
    function cancel(uint256[] calldata nonces) external {
        for (uint256 i; i < nonces.length; ++i) {
            records[msg.sender][nonces[i]] = IntentRecord.CANCELLED;
            emit IntentCancelled(msg.sender, nonces[i]);
        }
    }

    /// @notice The EIP-712 digest the owner signs.
    function hash(Intent calldata intent) public view returns (bytes32) {
        return _hashTypedDataV4(IntentHash.hash(intent));
    }

    function _useRecord(Intent memory intent) private {
        (uint8 verdict, uint256 updated) =
            IntentRecord.next(intent.constraints.lifetime, intent.start, records[intent.owner][intent.nonce]);
        if (verdict == IntentRecord.EXHAUSTED) {
            revert Exhausted();
        }
        if (verdict == IntentRecord.WAIT) {
            revert NotYet();
        }
        records[intent.owner][intent.nonce] = updated;
    }

    /// ECDSA first so EOAs and EIP-7702 accounts verify without a call, then ERC-1271 for contract
    /// wallets.
    function _isValidSignature(address signer, bytes32 digest, bytes calldata signature) private view returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return true;
        }
        return SignatureChecker.isValidERC1271SignatureNow(signer, digest, signature);
    }
}

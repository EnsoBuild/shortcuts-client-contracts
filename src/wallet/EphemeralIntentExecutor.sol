// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { Execution, IEphemeralFactory } from "../interfaces/IEphemeralFactory.sol";
import { Asset, Codes, InputSet, Intent } from "../interfaces/IIntent.sol";
import { IntentEvaluator, Run } from "../libraries/IntentEvaluator.sol";
import { IntentHash } from "../libraries/IntentHash.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract EphemeralIntentExecutor {
    error InvalidProof();

    /// The entire lifecycle runs in the constructor: the contract never deposits runtime code, and
    /// a selfdestruct in the creating transaction deletes the account (EIP-6780), so the address
    /// stays reusable and the code-deposit cost is never paid.
    /// @param root Merkle root over the intent tree's leaves; the address commits to it alone
    constructor(bytes32 root) {
        // Read once, before any external interaction: the factory's transient context is only
        // guaranteed for this construction.
        IEphemeralFactory factory = IEphemeralFactory(msg.sender);
        (bytes memory data, address caller, bytes32 domain) = factory.context();
        // The factory re-encodes nothing: this is the caller's own encoding, checked canonical.
        Execution memory e = abi.decode(data, (Execution));
        Intent memory intent = e.intent;

        // Hashing and proof verification can't revert and call no library, so they run before
        // branch selection without breaking the brick rules. A valid proof exists for every leaf of
        // the tree, so a bad one fails only its own caller's transaction.
        bytes32 leaf = IntentHash.leaf(intent);
        bool proven = MerkleProof.processProof(e.proof, leaf) == root;
        bool local = proven && intent.chainId == block.chainid;
        bool owned = caller == intent.owner;
        if (!local && !(proven && intent.chainId == 0 && owned)) {
            revert InvalidProof();
        }

        // A zero owner would burn native at the selfdestruct and strand every swept token.
        // Substitute the caller (never zero) rather than validate.
        address beneficiary = intent.owner == address(0) ? caller : intent.owner;

        // forge-lint: disable-next-item(block-timestamp)
        if (owned) {
            if (local && e.routes.length > 0 && e.routes[0].length > 0) {
                IntentEvaluator.ownerRoute(intent, e.router, e.routes[0]);
            } else {
                _refund(intent, e.sweep, caller, beneficiary, false);
            }
        } else if (intent.constraints.rules.length == 0 || block.timestamp > intent.deadline) {
            // Refund-only chains, and expired intents.
            _refund(intent, e.sweep, caller, beneficiary, true);
        } else {
            // The intent's identity: distinct per factory deployment and chain, keyed by the leaf.
            _execute(factory, root, e, caller, beneficiary, keccak256(bytes.concat(hex"1901", domain, leaf)));
        }

        // Remaining native rides the account deletion.
        selfdestruct(payable(beneficiary));
    }

    /// The execute arm. Every revert here is liveness-only: the funds stay and the refund arms
    /// remain open.
    function _execute(
        IEphemeralFactory factory,
        bytes32 root,
        Execution memory e,
        address caller,
        address beneficiary,
        bytes32 intentHash
    )
        private
    {
        Intent memory intent = e.intent;
        Run memory run = Run({
            id: intentHash,
            record: root,
            holder: address(this),
            owner: beneficiary,
            pull: false,
            caller: caller,
            records: address(factory),
            router: e.router,
            routes: e.routes,
            contexts: e.contexts
        });
        // Intents this version won't run (attestation, trace patterns, malformed structure, rules
        // that would leave the keeper's route unchecked, or a used-up record) come back with
        // nothing moved, and are refunded at once. The static refusals come before the keeper
        // gate, so their refund is open to anyone.
        if (IntentEvaluator.evaluate(intent, run) != IntentEvaluator.OK) {
            _refund(intent, e.sweep, caller, beneficiary, true);
            return;
        }
        // Tokens outside the input set always go back to the owner.
        for (uint256 i; i < e.sweep.length; ++i) {
            if (!_isInput(intent, e.sweep[i])) {
                _sweep(e.sweep[i], beneficiary);
            }
        }
    }

    /// Brick zone: every call here is tolerant. Fees first, best-effort, so permissionless refunds
    /// are self-incentivizing; then the inputs and the caller's list to the beneficiary.
    function _refund(Intent memory intent, Token[] memory sweep, address caller, address to, bool withFee) private {
        InputSet memory inputs = intent.constraints.inputs;
        Asset[] memory assets = intent.constraints.assets;
        uint256 n = inputs.assets.length;
        bool consistent = inputs.refundFees.length == n;
        for (uint256 p; p < n; ++p) {
            if (inputs.assets[p] >= assets.length) {
                continue; // malformed entry: skipped, never indexed
            }
            Asset memory a = assets[inputs.assets[p]];
            if (withFee && consistent && caller != intent.owner && caller != address(0)) {
                _tryPay(a, caller, inputs.refundFees[p]);
            }
            _sweep(a, to);
        }
        for (uint256 i; i < sweep.length; ++i) {
            _sweep(sweep[i], to);
        }
    }

    function _isInput(Intent memory intent, Token memory token) private pure returns (bool) {
        if (token.data.length < 32) {
            return false;
        }
        // Tolerant address decoding intentionally keeps the low 160 bits.
        // forge-lint: disable-next-line(unsafe-typecast)
        address asset = token.tokenType == TokenType.Native ? address(0) : address(uint160(_word(token.data, 0)));
        InputSet memory inputs = intent.constraints.inputs;
        for (uint256 p; p < inputs.assets.length; ++p) {
            if (inputs.assets[p] < intent.constraints.assets.length) {
                if (intent.constraints.assets[inputs.assets[p]].token == asset) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Best-effort fee in kind: skipped when held below the amount or the transfer fails.
    function _tryPay(Asset memory a, address to, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        if (a.kind == Codes.NATIVE) {
            if (address(this).balance >= amount) {
                // forge-lint: disable-next-line(arbitrary-send-eth)
                (bool success,) = to.call{ value: amount }("");
                (success); // best-effort
            }
        } else if (a.kind == Codes.ERC20 || a.kind == Codes.POSITION) {
            if (_tryBalance(a.token) >= amount) {
                _tryTransfer(a.token, to, amount);
            }
        }
    }

    /// Tolerant sweep of a named asset. Native is skipped; it rides the selfdestruct.
    function _sweep(Asset memory a, address to) private {
        uint8 kind = a.kind;
        if (kind == Codes.ERC20 || kind == Codes.POSITION) {
            _sweep(a.token, to);
        } else if (kind == Codes.ERC721) {
            // forge-lint: disable-next-item(calls-loop)
            (bool success,) = a.token.call(abi.encodeCall(IERC721.transferFrom, (address(this), to, a.id)));
            (success); // best-effort
        } else if (kind == Codes.ERC1155) {
            uint256 held = _tryRead(a.token, abi.encodeCall(IERC1155.balanceOf, (address(this), a.id)));
            if (held > 0) {
                // forge-lint: disable-next-item(calls-loop)
                (bool success,) =
                    a.token.call(abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, a.id, held, "")));
                (success); // best-effort
            }
        }
    }

    /// Best-effort full-balance sweep of a caller-listed token. Raw words, never abi.decode: the
    /// address- and contract-typed decoders revert on short data or dirty address words, and a
    /// revert here is a permanent brick.
    function _sweep(Token memory token, address to) private {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return;
        }
        if (token.data.length < (tokenType == TokenType.ERC1155 ? 96 : 64)) {
            return; // tolerant skip: a require here would re-create the brick
        }
        // Tolerant address decoding intentionally keeps the low 160 bits.
        // forge-lint: disable-next-line(unsafe-typecast)
        address asset = address(uint160(_word(token.data, 0)));
        if (tokenType == TokenType.ERC20) {
            _sweep(asset, to);
        } else if (tokenType == TokenType.ERC721) {
            // forge-lint: disable-next-item(calls-loop)
            (bool success,) =
                asset.call(abi.encodeCall(IERC721.transferFrom, (address(this), to, _word(token.data, 1))));
            (success); // best-effort
        } else {
            uint256 tokenId = _word(token.data, 1);
            uint256 held = _tryRead(asset, abi.encodeCall(IERC1155.balanceOf, (address(this), tokenId)));
            if (held == 0) {
                return;
            }
            // forge-lint: disable-next-item(calls-loop)
            (bool success,) =
                asset.call(abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, tokenId, held, "")));
            (success); // best-effort
        }
    }

    function _sweep(address token, address to) private {
        if (token == address(0)) {
            return;
        }
        uint256 held = _tryBalance(token);
        if (held == 0) {
            return;
        }
        _tryTransfer(token, to, held);
    }

    function _tryBalance(address token) private view returns (uint256) {
        return _tryRead(token, abi.encodeCall(IERC20.balanceOf, (address(this))));
    }

    /// Tolerant uint read: staticcall the probe, zero on failure or a short return.
    function _tryRead(address target, bytes memory probe) private view returns (uint256) {
        // forge-lint: disable-next-line(calls-loop)
        (bool success, bytes memory ret) = target.staticcall(probe);
        if (!success || ret.length < 32) {
            return 0;
        }
        return abi.decode(ret, (uint256));
    }

    /// transfer() tolerant of missing return data; false for false-returning tokens and for any
    /// non-canonical return shape. The length check must stay inside the boolean expression:
    /// _word is an unguarded mload relying on && short-circuit.
    function _tryTransfer(address token, address to, uint256 amount) private returns (bool success) {
        bytes memory ret;
        // forge-lint: disable-next-line(calls-loop)
        (success, ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        success = success && (ret.length == 0 || (ret.length >= 32 && _word(ret, 0) == 1));
    }

    function _word(bytes memory data, uint256 index) private pure returns (uint256 word) {
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x20), shl(5, index)))
        }
    }
}

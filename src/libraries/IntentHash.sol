// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {
    Asset,
    Constraints,
    Consume,
    Handoff,
    InputSet,
    Intent,
    Lifetime,
    Param,
    Pattern,
    Predicate,
    Request,
    Rule,
    Source,
    Term,
    View
} from "../interfaces/IIntent.sol";

/// @title IntentHash
/// @notice Hashing for the version 2 Intent. `hash` is the EIP-712 struct hash an owner signs under a
///         router's domain. `leaf` is the commitment an ephemeral intent tree holds: nothing signs a
///         leaf, so it uses the far cheaper ABI hash of the same struct.
library IntentHash {
    string internal constant ASSET = "Asset(uint8 kind,uint256 chainId,address token,uint256 id)";
    string internal constant CONSUME = "Consume(uint16 source,bytes32 key,uint16 amount,uint256 cap,uint64 period)";
    string internal constant CONSTRAINTS = "Constraints(Lifetime lifetime,uint8 frame,uint8 matching,address router,"
        "address[] accounts,Asset[] assets,Source[] sources,View[] views,Pattern[] patterns,InputSet inputs,"
        "Term[] terms,Handoff[] handoffs,Consume[] consumes,Predicate[] predicates,Rule[] rules)";
    string internal constant HANDOFF = "Handoff(uint16 source,uint256 chainId,bytes32 method,address recipient,"
        "address refund,uint16 input,uint16 asset,uint16 minAmount,uint16 deadline)";
    string internal constant INPUT_SET =
        "InputSet(uint16[] assets,uint256[] minimums,uint16[] prices,uint256[] refundFees,uint8 threshold)";
    string internal constant INTENT = "Intent(uint16 version,uint256 chainId,uint256 nonce,uint64 start,"
        "uint64 deadline,address owner,address keeper,uint64 exclusive,Constraints constraints)";
    string internal constant LIFETIME = "Lifetime(uint8 kind,uint64 interval,uint32 count)";
    string internal constant PARAM = "Param(bytes32 name,uint8 kind,uint16 index)";
    string internal constant PATTERN =
        "Pattern(uint8 kind,address target,bytes32 sig,bytes32[] args,uint256 wildcards)";
    string internal constant PREDICATE =
        "Predicate(uint8 cmp,uint16 lhs,uint16 rhs,uint8 enforce,uint16 source,uint8 group)";
    string internal constant REQUEST = "Request(bytes32 api,string body,Param[] params)";
    string internal constant RULE = "Rule(uint16[] inputs,uint16[] when,uint16[] then,uint16 feeAsset,uint16 fee,"
        "uint8 consume,bytes route,Request request)";
    string internal constant SOURCE = "Source(uint8 kind,address target,bytes config)";
    string internal constant TERM = "Term(uint8 op,uint16 a,uint16 b,uint256 value,bytes data)";
    string internal constant VIEW = "View(address target,bytes4 selector,bytes args,uint8 word)";

    // Referenced types follow the primary type in alphabetical order (EIP-712 encodeType).
    bytes32 internal constant INTENT_TYPEHASH = keccak256(
        abi.encodePacked(
            INTENT,
            ASSET,
            CONSTRAINTS,
            CONSUME,
            HANDOFF,
            INPUT_SET,
            LIFETIME,
            PARAM,
            PATTERN,
            PREDICATE,
            REQUEST,
            RULE,
            SOURCE,
            TERM,
            VIEW
        )
    );
    bytes32 internal constant CONSTRAINTS_TYPEHASH = keccak256(
        abi.encodePacked(
            CONSTRAINTS,
            ASSET,
            CONSUME,
            HANDOFF,
            INPUT_SET,
            LIFETIME,
            PARAM,
            PATTERN,
            PREDICATE,
            REQUEST,
            RULE,
            SOURCE,
            TERM,
            VIEW
        )
    );
    bytes32 internal constant ASSET_TYPEHASH = keccak256(bytes(ASSET));
    bytes32 internal constant CONSUME_TYPEHASH = keccak256(bytes(CONSUME));
    bytes32 internal constant HANDOFF_TYPEHASH = keccak256(bytes(HANDOFF));
    bytes32 internal constant INPUT_SET_TYPEHASH = keccak256(bytes(INPUT_SET));
    bytes32 internal constant LIFETIME_TYPEHASH = keccak256(bytes(LIFETIME));
    bytes32 internal constant PARAM_TYPEHASH = keccak256(bytes(PARAM));
    bytes32 internal constant PATTERN_TYPEHASH = keccak256(bytes(PATTERN));
    bytes32 internal constant PREDICATE_TYPEHASH = keccak256(bytes(PREDICATE));
    bytes32 internal constant REQUEST_TYPEHASH = keccak256(abi.encodePacked(REQUEST, PARAM));
    bytes32 internal constant RULE_TYPEHASH = keccak256(abi.encodePacked(RULE, PARAM, REQUEST));
    bytes32 internal constant SOURCE_TYPEHASH = keccak256(bytes(SOURCE));
    bytes32 internal constant TERM_TYPEHASH = keccak256(bytes(TERM));
    bytes32 internal constant VIEW_TYPEHASH = keccak256(bytes(VIEW));

    /// @notice EIP-712 hashStruct(intent).
    function hash(Intent memory intent) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                intent.version,
                intent.chainId,
                intent.nonce,
                intent.start,
                intent.deadline,
                intent.owner,
                intent.keeper,
                intent.exclusive,
                _constraints(intent.constraints)
            )
        );
    }

    /// @notice The Merkle leaf of an intent: its ABI hash, hashed again so no leaf can pass as an
    ///         internal node. Internal, so verifying a proof depends on no deployed library.
    function leaf(Intent memory intent) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(intent))));
    }

    function _constraints(Constraints memory c) private pure returns (bytes32) {
        // Two encodes: a single abi.encode of every field exceeds the stack.
        bytes memory head = abi.encode(
            CONSTRAINTS_TYPEHASH,
            _lifetime(c.lifetime),
            c.frame,
            c.matching,
            c.router,
            keccak256(abi.encodePacked(c.accounts)),
            _assets(c.assets),
            _sources(c.sources),
            _views(c.views)
        );
        bytes memory tail = abi.encode(
            _patterns(c.patterns),
            _inputs(c.inputs),
            _terms(c.terms),
            _handoffs(c.handoffs),
            _consumes(c.consumes),
            _predicates(c.predicates),
            _rules(c.rules)
        );
        return keccak256(bytes.concat(head, tail));
    }

    function _lifetime(Lifetime memory l) private pure returns (bytes32) {
        return keccak256(abi.encode(LIFETIME_TYPEHASH, l.kind, l.interval, l.count));
    }

    function _assets(Asset[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Asset memory a = items[i];
            hashes[i] = keccak256(abi.encode(ASSET_TYPEHASH, a.kind, a.chainId, a.token, a.id));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _sources(Source[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Source memory s = items[i];
            hashes[i] = keccak256(abi.encode(SOURCE_TYPEHASH, s.kind, s.target, keccak256(s.config)));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _views(View[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            View memory v = items[i];
            hashes[i] = keccak256(abi.encode(VIEW_TYPEHASH, v.target, v.selector, keccak256(v.args), v.word));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _patterns(Pattern[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Pattern memory p = items[i];
            hashes[i] = keccak256(
                abi.encode(PATTERN_TYPEHASH, p.kind, p.target, p.sig, keccak256(abi.encodePacked(p.args)), p.wildcards)
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _inputs(InputSet memory s) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INPUT_SET_TYPEHASH,
                keccak256(abi.encodePacked(s.assets)),
                keccak256(abi.encodePacked(s.minimums)),
                keccak256(abi.encodePacked(s.prices)),
                keccak256(abi.encodePacked(s.refundFees)),
                s.threshold
            )
        );
    }

    function _terms(Term[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Term memory t = items[i];
            hashes[i] = keccak256(abi.encode(TERM_TYPEHASH, t.op, t.a, t.b, t.value, keccak256(t.data)));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _handoffs(Handoff[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Handoff memory h = items[i];
            hashes[i] = keccak256(
                abi.encode(
                    HANDOFF_TYPEHASH,
                    h.source,
                    h.chainId,
                    h.method,
                    h.recipient,
                    h.refund,
                    h.input,
                    h.asset,
                    h.minAmount,
                    h.deadline
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _consumes(Consume[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Consume memory c = items[i];
            hashes[i] = keccak256(abi.encode(CONSUME_TYPEHASH, c.source, c.key, c.amount, c.cap, c.period));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _predicates(Predicate[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Predicate memory p = items[i];
            hashes[i] = keccak256(abi.encode(PREDICATE_TYPEHASH, p.cmp, p.lhs, p.rhs, p.enforce, p.source, p.group));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _rules(Rule[] memory items) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](items.length);
        for (uint256 i; i < items.length; ++i) {
            Rule memory r = items[i];
            hashes[i] = keccak256(
                abi.encode(
                    RULE_TYPEHASH,
                    keccak256(abi.encodePacked(r.inputs)),
                    keccak256(abi.encodePacked(r.when)),
                    keccak256(abi.encodePacked(r.then)),
                    r.feeAsset,
                    r.fee,
                    r.consume,
                    keccak256(r.route),
                    _request(r.request)
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _request(Request memory q) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](q.params.length);
        for (uint256 i; i < q.params.length; ++i) {
            Param memory p = q.params[i];
            hashes[i] = keccak256(abi.encode(PARAM_TYPEHASH, p.name, p.kind, p.index));
        }
        return
            keccak256(
                abi.encode(REQUEST_TYPEHASH, q.api, keccak256(bytes(q.body)), keccak256(abi.encodePacked(hashes)))
            );
    }
}

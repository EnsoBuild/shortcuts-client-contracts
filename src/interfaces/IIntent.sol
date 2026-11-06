// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// Shared intent format, version 2: the EIP-712 message IntentRouter executes, and a leaf of the
/// Merkle tree an ephemeral intent address commits to. One intent covers one chain.
struct Intent {
    uint16 version; // semantics version of the constraint language; enforced
    uint256 chainId; // execution chain; 0 = a tree's default leaf
    uint256 nonce; // router: unordered replay nonce; ephemeral: distinguishes otherwise-identical intents
    uint64 start;
    uint64 deadline;
    address owner; // signer (router); refund beneficiary and owner arms (ephemeral)
    address keeper; // the only account that may execute; address(0) = any caller
    uint64 exclusive; // keeper-only until this time, then anyone; 0 = keeper-only for the intent's life
    Constraints constraints;
}

struct Constraints {
    Lifetime lifetime;
    uint8 frame; // Codes.FRAME_*
    uint8 matching; // Codes.MATCH_*
    address router; // the execution layer bundles run through; address(0) = keeper's choice
    address[] accounts; // accounts 2+; 0 = holder, 1 = owner
    Asset[] assets;
    Source[] sources;
    View[] views;
    Pattern[] patterns;
    InputSet inputs;
    Term[] terms;
    Handoff[] handoffs;
    Consume[] consumes;
    Predicate[] predicates;
    Rule[] rules;
}

struct Lifetime {
    uint8 kind; // Codes.ONCE | Codes.STANDING
    uint64 interval; // seconds per window, anchored at Intent.start; 0 = no schedule
    uint32 count; // maximum executions; 0 = unlimited
}

struct Asset {
    uint8 kind; // Codes.NATIVE | ERC20 | ERC721 | ERC1155 | POSITION
    uint256 chainId; // lets destination-chain assets be named
    address token;
    uint256 id; // ERC721/ERC1155 id; unused otherwise
}

struct InputSet {
    uint16[] assets; // allowlist of asset indices
    uint256[] minimums; // per asset: below this the asset counts as absent; the EXACT amount
    uint16[] prices; // per asset: ORACLE source for CONSUMED_VALUE; Codes.NONE for none
    uint256[] refundFees; // per asset: fixed fee, in that asset, for refunding it
    uint8 threshold; // k-of-n: 1 = ANY, assets.length = ALL; 0 with no assets = no inputs
}

struct View {
    address target;
    bytes4 selector;
    bytes args; // ABI-encoded arguments
    uint8 word; // which 32-byte word of the return data to read
}

struct Pattern {
    uint8 kind; // Codes.EVENT | CALL | DELEGATECALL
    address target; // zero = any
    bytes32 sig; // event topic0 or selector; zero = any
    bytes32[] args;
    uint256 wildcards; // bit i set = args[i] matches any value
}

struct Term {
    uint8 op; // Codes.OP_*
    uint16 a; // operand index; what it indexes depends on op
    uint16 b;
    uint256 value; // constants, quote-asset index, bps, counter period
    bytes data; // counter keys; otherwise empty
}

struct Predicate {
    uint8 cmp; // Codes.CMP_*
    uint16 lhs; // term index, or handoff/consume/pattern index for unary checks
    uint16 rhs; // term index
    uint8 enforce; // Codes.ONCHAIN | ATTESTED | BOTH
    uint16 source; // the ATTESTED source enforcing it when ATTESTED or BOTH; Codes.NONE when ONCHAIN
    uint8 group; // within a rule's list: same group = AND; groups are ORed
}

struct Rule {
    uint16[] inputs; // InputSet positions this rule consumes
    uint16[] when; // predicate indices: the guard; empty = active iff any input is present (always, if none)
    uint16[] then; // predicate indices that must hold when the rule is active
    uint16 feeAsset; // asset the keeper's fee is paid in; Codes.NONE for no fee
    uint16 fee; // term index: the keeper's fee; Codes.NONE for no fee
    uint8 consume; // Codes.EXACT | Codes.DRAIN
    bytes route; // committed shortcut data for the router; empty = the keeper supplies this rule's bytes
    Request request; // what the keeper builds this rule's route from, when route is empty
}

struct Request {
    bytes32 api; // keccak256 of the operation and schema version; 0 = no request
    string body; // canonical JSON (RFC 8785) with {$name} placeholders
    Param[] params;
}

struct Param {
    bytes32 name;
    uint8 kind; // Codes.PARAM_*
    uint16 index; // account, asset or term index; unused for CHAIN
}

struct Consume {
    uint16 source; // a COUNTER source
    bytes32 key;
    uint16 amount; // term index
    uint256 cap; // per period
    uint64 period; // seconds; 0 = lifetime of the intent
}

struct Handoff {
    uint16 source; // a GUARDIAN source
    uint256 chainId; // where delivery happens; may be the execution chain
    bytes32 method; // keccak256 of the delivery method's name; 0 = any
    address recipient;
    address refund; // receives refunds the delivery method itself makes; never the intent address
    uint16 input; // source-chain asset handed to the guardian
    uint16 asset; // delivered asset (Asset.chainId == chainId)
    uint16 minAmount; // term index
    uint16 deadline; // term index
}

struct Source {
    uint8 kind; // Codes.ORACLE | GUARDIAN | COUNTER | ATTESTED
    address target;
    bytes config; // ORACLE: (uint32 staleness); GUARDIAN: (uint8 level); COUNTER: empty
}

/// Numeric codes for the uint8 fields above. Values are part of the signed format: never renumber.
library Codes {
    uint16 internal constant VERSION = 2;
    uint16 internal constant NONE = type(uint16).max;

    // Lifetime.kind
    uint8 internal constant ONCE = 0;
    uint8 internal constant STANDING = 1;

    // Constraints.frame
    uint8 internal constant FRAME_NONE = 0;
    uint8 internal constant FRAME_STRICT = 1;

    // Constraints.matching
    uint8 internal constant MATCH_ALL = 0;
    uint8 internal constant MATCH_FIRST = 1;

    // Asset.kind
    uint8 internal constant NATIVE = 0;
    uint8 internal constant ERC20 = 1;
    uint8 internal constant ERC721 = 2;
    uint8 internal constant ERC1155 = 3;
    uint8 internal constant POSITION = 4;

    // Source.kind
    uint8 internal constant ORACLE = 0;
    uint8 internal constant GUARDIAN = 1;
    uint8 internal constant COUNTER = 2;
    uint8 internal constant ATTESTED = 3;

    // Pattern.kind
    uint8 internal constant EVENT = 0;
    uint8 internal constant CALL = 1;
    uint8 internal constant DELEGATECALL = 2;

    // Term.op
    uint8 internal constant OP_CONST = 0;
    uint8 internal constant OP_NOW = 1;
    uint8 internal constant OP_BALANCE = 2;
    uint8 internal constant OP_DELTA = 3;
    uint8 internal constant OP_PRE_VIEW = 4;
    uint8 internal constant OP_POST_VIEW = 5;
    uint8 internal constant OP_SOURCE = 6;
    uint8 internal constant OP_CONSUMED = 7;
    uint8 internal constant OP_CONSUMED_VALUE = 8;
    uint8 internal constant OP_ADD = 9;
    uint8 internal constant OP_SUB = 10;
    uint8 internal constant OP_MUL = 11;
    uint8 internal constant OP_DIV = 12;
    uint8 internal constant OP_MUL_BPS = 13;

    // Predicate.cmp
    uint8 internal constant CMP_GTE = 0;
    uint8 internal constant CMP_GT = 1;
    uint8 internal constant CMP_LTE = 2;
    uint8 internal constant CMP_LT = 3;
    uint8 internal constant CMP_EQ = 4;
    uint8 internal constant CMP_ACCEPTED = 5;
    uint8 internal constant CMP_CONSUMED_WITHIN = 6;
    uint8 internal constant CMP_EMITS = 7;
    uint8 internal constant CMP_NEVER = 8;

    // Predicate.enforce
    uint8 internal constant ONCHAIN = 0;
    uint8 internal constant ENFORCE_ATTESTED = 1;
    uint8 internal constant BOTH = 2;

    // Rule.consume
    uint8 internal constant EXACT = 0;
    uint8 internal constant DRAIN = 1;

    // Param.kind
    uint8 internal constant PARAM_ACCOUNT = 0;
    uint8 internal constant PARAM_ASSET = 1;
    uint8 internal constant PARAM_TERM = 2;
    uint8 internal constant PARAM_CHAIN = 3;

    // Account indices
    uint16 internal constant HOLDER = 0;
    uint16 internal constant OWNER = 1;
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IEphemeralFactory } from "../interfaces/IEphemeralFactory.sol";
import {
    Asset,
    Codes,
    Constraints,
    Consume,
    Handoff,
    InputSet,
    Intent,
    Predicate,
    Rule,
    Source,
    Term,
    View
} from "../interfaces/IIntent.sol";
import { IIntentCounter } from "../interfaces/IIntentCounter.sol";
import { IIntentGuardian, Level, Obligation } from "../interfaces/IIntentGuardian.sol";
import { IIntentOracle } from "../interfaces/IIntentOracle.sol";
import { IntentRecord } from "./IntentRecord.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";

/// How the calling contract holds the intent's funds.
struct Run {
    bytes32 id; // intentHash: the EIP-712 digest under the executing contract's domain
    bytes32 record; // counter key: the tree root (ephemeral) or the digest (router)
    address holder; // whose balances the intent constrains: the intent address, or the owner
    address owner; // account 1
    bool pull; // router: inputs are pulled from the holder into this contract before use
    address caller; // the executing keeper, paid the rule fees
    address records; // the ephemeral factory holding this executor's record; address(0) = caller keeps it
    address router; // keeper's router, used only when the constraints name none
    bytes[] routes; // keeper bytes per rule, used only by rules without a committed route
    bytes[] contexts; // keeper context per handoff
}

/// @title IntentEvaluator
/// @notice Evaluates version 2 constraints. Linked into EphemeralIntentExecutor and IntentRouter and
///         run by delegatecall, so every approval, transfer and call is made as the calling contract.
/// @dev This version executes no attestation: intents with attested predicates or sources, or trace
///      patterns, are reported UNSUPPORTED. Rules that leave the keeper's route unchecked are
///      reported CUSTODIAL. Callers refuse both.
library IntentEvaluator {
    using SafeERC20 for IERC20;

    uint8 internal constant OK = 0;
    uint8 internal constant MALFORMED = 1;
    uint8 internal constant UNSUPPORTED = 2;
    uint8 internal constant CUSTODIAL = 3;
    uint8 internal constant EXHAUSTED = 4; // used up or cancelled (ephemeral records)

    error NotKeeper();
    error TooEarly();
    error NotYet();
    error NotExecutable();
    error NoRouter();
    error Overflow();
    error DivisionByZero();
    error Stale(uint16 source);
    error ViewFailed(uint16 view_);
    error WrongLevel(uint16 handoff);
    error PredicateFailed(uint16 rule);
    error FrameViolation(uint16 asset);
    error ApprovalLeft(address token, address spender);
    error UnsupportedAsset(uint16 asset);

    struct State {
        bool[] present; // per input position
        uint256[] consumed; // per input position; includes the rule fee when paid in that asset
        bool[] active; // per rule
        bool[] post; // per term: depends on post-state
        bool[] scoped; // per term: depends on CONSUMED_VALUE
        int256[] memo;
        bool[] known;
        int256[][] scopedMemo; // per active rule
        bool[][] scopedKnown;
        uint256[] deltaPre; // per term: pre balance for DELTA terms
        bool postPhase;
        bool[] accepted; // per handoff
        uint256[] framePre; // per asset: holder balance before execution
        uint256[] fees; // per rule: fee paid
        address router;
        address[] grantedToken;
        address[] grantedSpender;
        uint256 granted;
    }

    // ---------------------------------------------------------------------------------------------
    // Static check
    // ---------------------------------------------------------------------------------------------

    /// @notice Static validation. Never reverts: every index is bounds-checked, so a malformed
    ///         committed intent reports MALFORMED instead of bricking a refund decision.
    function check(Intent memory intent) public pure returns (uint8) {
        if (intent.version != Codes.VERSION) {
            return UNSUPPORTED;
        }
        Constraints memory c = intent.constraints;
        if (c.lifetime.kind > Codes.STANDING || c.frame > Codes.FRAME_STRICT || c.matching > Codes.MATCH_FIRST) {
            return MALFORMED;
        }
        if (c.patterns.length > 0) {
            return UNSUPPORTED; // trace facts are attestation-only
        }
        for (uint256 i; i < c.assets.length; ++i) {
            if (c.assets[i].kind > Codes.POSITION) {
                return MALFORMED;
            }
        }
        for (uint256 i; i < c.sources.length; ++i) {
            Source memory s = c.sources[i];
            if (s.kind == Codes.ATTESTED) {
                return UNSUPPORTED;
            }
            if (
                s.kind > Codes.ATTESTED
                    || ((s.kind == Codes.ORACLE || s.kind == Codes.GUARDIAN) && s.config.length < 32)
            ) {
                return MALFORMED;
            }
        }
        uint8 status = _checkInputs(c);
        if (status != OK) {
            return status;
        }
        (bool[] memory post, bool[] memory consumed, uint8 termStatus) = _checkTerms(c);
        if (termStatus != OK) {
            return termStatus;
        }
        status = _checkPredicates(c);
        if (status != OK) {
            return status;
        }
        status = _checkHandoffs(c, post);
        if (status != OK) {
            return status;
        }
        if (intent.chainId == 0 && (c.rules.length > 0 || c.inputs.assets.length > 0)) {
            return MALFORMED; // a default leaf only refunds
        }
        return _checkRules(c, post, consumed);
    }

    function _checkInputs(Constraints memory c) private pure returns (uint8) {
        InputSet memory s = c.inputs;
        uint256 n = s.assets.length;
        if (s.minimums.length != n || s.prices.length != n || s.refundFees.length != n || n > 256) {
            return MALFORMED;
        }
        if (s.threshold > n || (n > 0 && s.threshold == 0)) {
            return MALFORMED;
        }
        for (uint256 p; p < n; ++p) {
            if (s.assets[p] >= c.assets.length) {
                return MALFORMED;
            }
            uint16 price = s.prices[p];
            if (price != Codes.NONE && (price >= c.sources.length || c.sources[price].kind != Codes.ORACLE)) {
                return MALFORMED;
            }
            uint8 kind = c.assets[s.assets[p]].kind;
            if (kind == Codes.ERC1155 && c.router == address(0)) {
                return UNSUPPORTED; // collection-wide approval to a keeper-chosen router
            }
        }
        return OK;
    }

    /// @return post Per term: depends on post-state
    /// @return consumed Per term: depends on what the active rules consume
    function _checkTerms(Constraints memory c)
        private
        pure
        returns (bool[] memory post, bool[] memory consumed, uint8)
    {
        uint256 accountCount = c.accounts.length + 2;
        post = new bool[](c.terms.length);
        consumed = new bool[](c.terms.length);
        for (uint256 i; i < c.terms.length; ++i) {
            Term memory t = c.terms[i];
            uint8 op = t.op;
            if (op == Codes.OP_BALANCE || op == Codes.OP_DELTA) {
                if (t.a >= c.assets.length || t.b >= accountCount) {
                    return (post, consumed, MALFORMED);
                }
                post[i] = op == Codes.OP_DELTA;
            } else if (op == Codes.OP_PRE_VIEW || op == Codes.OP_POST_VIEW) {
                if (t.a >= c.views.length) {
                    return (post, consumed, MALFORMED);
                }
                post[i] = op == Codes.OP_POST_VIEW;
            } else if (op == Codes.OP_SOURCE) {
                if (t.a >= c.sources.length) {
                    return (post, consumed, MALFORMED);
                }
                uint8 kind = c.sources[t.a].kind;
                if (kind == Codes.ORACLE) {
                    if (t.b >= c.assets.length || t.value >= c.assets.length) {
                        return (post, consumed, MALFORMED);
                    }
                } else if (kind != Codes.COUNTER || t.data.length != 32) {
                    return (post, consumed, MALFORMED);
                }
            } else if (op == Codes.OP_CONSUMED || op == Codes.OP_CONSUMED_VALUE) {
                if (t.a >= c.assets.length) {
                    return (post, consumed, MALFORMED);
                }
                consumed[i] = true;
            } else if (op >= Codes.OP_ADD && op <= Codes.OP_MUL_BPS) {
                // Operands come first, so evaluation needs no cycle detection.
                bool binary = op != Codes.OP_MUL_BPS;
                if (t.a >= i || (binary && t.b >= i)) {
                    return (post, consumed, MALFORMED);
                }
                post[i] = post[t.a] || (binary && post[t.b]);
                consumed[i] = consumed[t.a] || (binary && consumed[t.b]);
            } else if (op > Codes.OP_MUL_BPS) {
                return (post, consumed, MALFORMED);
            }
        }
        return (post, consumed, OK);
    }

    function _checkPredicates(Constraints memory c) private pure returns (uint8) {
        for (uint256 i; i < c.predicates.length; ++i) {
            Predicate memory p = c.predicates[i];
            if (p.enforce != Codes.ONCHAIN) {
                return p.enforce > Codes.BOTH ? MALFORMED : UNSUPPORTED;
            }
            if (p.cmp == Codes.CMP_EMITS || p.cmp == Codes.CMP_NEVER) {
                return UNSUPPORTED;
            }
            if (p.cmp <= Codes.CMP_EQ) {
                if (p.lhs >= c.terms.length || p.rhs >= c.terms.length) {
                    return MALFORMED;
                }
            } else if (p.cmp == Codes.CMP_ACCEPTED) {
                if (p.lhs >= c.handoffs.length) {
                    return MALFORMED;
                }
            } else if (p.cmp == Codes.CMP_CONSUMED_WITHIN) {
                if (p.lhs >= c.consumes.length) {
                    return MALFORMED;
                }
            } else {
                return MALFORMED;
            }
        }
        for (uint256 i; i < c.consumes.length; ++i) {
            Consume memory k = c.consumes[i];
            if (k.source >= c.sources.length || c.sources[k.source].kind != Codes.COUNTER || k.amount >= c.terms.length)
            {
                return MALFORMED;
            }
        }
        return OK;
    }

    function _checkHandoffs(Constraints memory c, bool[] memory post) private pure returns (uint8) {
        for (uint256 i; i < c.handoffs.length; ++i) {
            Handoff memory h = c.handoffs[i];
            if (h.source >= c.sources.length || c.sources[h.source].kind != Codes.GUARDIAN) {
                return MALFORMED;
            }
            if (h.input >= c.assets.length || h.asset >= c.assets.length) {
                return MALFORMED;
            }
            if (h.minAmount >= c.terms.length || h.deadline >= c.terms.length) {
                return MALFORMED;
            }
            // Handoff terms are needed before accept runs: pre-state only.
            if (post[h.minAmount] || post[h.deadline]) {
                return MALFORMED;
            }
        }
        return OK;
    }

    function _checkRules(Constraints memory c, bool[] memory post, bool[] memory consumed)
        private
        pure
        returns (uint8)
    {
        uint256 covered;
        uint256 n = c.inputs.assets.length;
        bool any = c.inputs.threshold < n;
        for (uint256 r; r < c.rules.length; ++r) {
            Rule memory rule = c.rules[r];
            if (rule.consume > Codes.DRAIN) {
                return MALFORMED;
            }
            for (uint256 j; j < rule.inputs.length; ++j) {
                uint16 p = rule.inputs[j];
                if (p >= n) {
                    return MALFORMED;
                }
                uint256 bit = uint256(1) << p;
                // Under ALL matching, each input counts toward exactly one rule.
                if (c.matching == Codes.MATCH_ALL && covered & bit != 0) {
                    return MALFORMED;
                }
                covered |= bit;
            }
            if (any && c.lifetime.kind == Codes.ONCE && rule.inputs.length > 0 && rule.consume != Codes.DRAIN) {
                return MALFORMED; // a keeper could take the profitable input and strand the rest
            }
            if ((rule.feeAsset == Codes.NONE) != (rule.fee == Codes.NONE)) {
                return MALFORMED;
            }
            if (
                rule.fee != Codes.NONE
                    && (rule.fee >= c.terms.length || rule.feeAsset >= c.assets.length || post[rule.fee])
            ) {
                return MALFORMED;
            }
            if (rule.route.length > 0 && c.router == address(0)) {
                return MALFORMED; // committed shortcut data is specific to a router
            }
            for (uint256 j; j < rule.when.length; ++j) {
                if (rule.when[j] >= c.predicates.length) {
                    return MALFORMED;
                }
                Predicate memory p = c.predicates[rule.when[j]];
                // Guards read pre-state only, so the active rules are fixed before the keeper acts,
                // and never what the rules consume, which depends on which rules are active.
                if (p.cmp > Codes.CMP_EQ || post[p.lhs] || post[p.rhs] || consumed[p.lhs] || consumed[p.rhs]) {
                    return MALFORMED;
                }
            }
            for (uint256 j; j < rule.then.length; ++j) {
                if (rule.then[j] >= c.predicates.length) {
                    return MALFORMED;
                }
            }
            if (rule.route.length == 0 && !_bounded(c, rule, post)) {
                return CUSTODIAL;
            }
        }
        // Every input is consumed by some rule, except in refund-only constraints.
        if (c.rules.length > 0 && n > 0 && covered != (n == 256 ? type(uint256).max : (uint256(1) << n) - 1)) {
            return MALFORMED;
        }
        return OK;
    }

    /// Every OR group of a keeper-routed rule's outcome holds at least one candidate bound: a
    /// handoff, or a lower bound on post-state against a pre-state value. The value's sign is
    /// checked at execution.
    function _bounded(Constraints memory c, Rule memory rule, bool[] memory post) private pure returns (bool) {
        uint256 seen;
        uint256 bounded;
        for (uint256 j; j < rule.then.length; ++j) {
            Predicate memory p = c.predicates[rule.then[j]];
            uint256 bit = uint256(1) << p.group;
            seen |= bit;
            if (_candidate(p, post)) {
                bounded |= bit;
            }
        }
        return seen != 0 && seen == bounded;
    }

    function _candidate(Predicate memory p, bool[] memory post) private pure returns (bool) {
        if (p.cmp == Codes.CMP_ACCEPTED) {
            return true;
        }
        return (p.cmp == Codes.CMP_GTE || p.cmp == Codes.CMP_GT || p.cmp == Codes.CMP_EQ) && post[p.lhs] && !post[p.rhs];
    }

    // ---------------------------------------------------------------------------------------------
    // Execution
    // ---------------------------------------------------------------------------------------------

    /// @notice Check, gate and execute in one call, so the intent crosses into the library once.
    /// @return status OK when executed. Any other status means nothing changed: MALFORMED,
    ///         UNSUPPORTED or CUSTODIAL (statically, or at the pre-state when a keeper-routed rule's
    ///         bound isn't positive), or EXHAUSTED. Liveness failures revert: NotKeeper, TooEarly,
    ///         NotYet, and anything execution itself raises.
    /// @dev The static check runs before the keeper gate, so a refused intent's refund is open to
    ///      anyone; the runtime custody test runs after it.
    function evaluate(Intent memory intent, Run memory run) public returns (uint8 status) {
        status = check(intent);
        if (status != OK) {
            return status;
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (
            intent.keeper != address(0) && run.caller != intent.keeper
                && (intent.exclusive == 0 || block.timestamp < intent.exclusive)
        ) {
            revert NotKeeper();
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (block.timestamp < intent.start) {
            revert TooEarly();
        }
        bool recorded = run.records != address(0) && IntentRecord.needed(intent.constraints.lifetime);
        if (recorded) {
            uint8 verdict =
                IEphemeralFactory(run.records).verdict(address(this), intent.constraints.lifetime, intent.start);
            if (verdict == IntentRecord.EXHAUSTED) {
                return EXHAUSTED;
            }
            if (verdict == IntentRecord.WAIT) {
                revert NotYet();
            }
        }
        if (!_execute(intent, run)) {
            return CUSTODIAL;
        }
        if (recorded) {
            IEphemeralFactory(run.records).record(intent.constraints.lifetime, intent.start);
        }
    }

    /// @return executed False when, at the pre-state, some keeper-routed rule has no positive outcome
    ///         bound: nothing was changed, and the caller treats the intent as custodial
    function _execute(Intent memory intent, Run memory run) private returns (bool executed) {
        Constraints memory c = intent.constraints;
        State memory s = _state(c);
        s.router = c.router != address(0) ? c.router : run.router;

        _snapshot(c, run, s);
        _selectRules(c, run, s);
        if (!_positive(c, run, s)) {
            return false;
        }
        _payFees(c, run, s);
        _routes(c, run, s);
        _handoffs(c, run, s);
        s.postPhase = true;
        _outcomes(c, run, s);
        if (c.frame == Codes.FRAME_STRICT) {
            _frame(c, run, s);
        }
        return true;
    }

    /// @notice The owner's route: every input of this chain at its live balance through the router,
    ///         unvalidated. The owner's own transaction; ephemeral executors only.
    function ownerRoute(Intent memory intent, address keeperRouter, bytes memory data) public {
        Constraints memory c = intent.constraints;
        address router = c.router != address(0) ? c.router : keeperRouter;
        if (router == address(0)) {
            revert NoRouter();
        }
        uint256 n = c.inputs.assets.length;
        Token[] memory tokens = new Token[](n);
        uint256 count;
        uint256 value;
        for (uint256 p; p < n; ++p) {
            Asset memory a = c.assets[c.inputs.assets[p]];
            uint256 amount = _balanceOf(a, address(this));
            if (amount == 0) {
                continue;
            }
            tokens[count++] = _token(a, amount);
            if (a.kind == Codes.NATIVE) {
                value = amount;
            } else {
                _grant(a, router, amount);
            }
        }
        assembly ("memory-safe") {
            mstore(tokens, count)
        }
        IEnsoRouter(router).routeMulti{ value: value }(tokens, data);
        for (uint256 i; i < count; ++i) {
            _revokeToken(tokens[i], router);
        }
    }

    function _state(Constraints memory c) private pure returns (State memory s) {
        uint256 n = c.inputs.assets.length;
        uint256 terms = c.terms.length;
        s.present = new bool[](n);
        s.consumed = new uint256[](n);
        s.active = new bool[](c.rules.length);
        s.post = new bool[](terms);
        s.scoped = new bool[](terms);
        s.memo = new int256[](terms);
        s.known = new bool[](terms);
        s.scopedMemo = new int256[][](c.rules.length);
        s.scopedKnown = new bool[][](c.rules.length);
        s.deltaPre = new uint256[](terms);
        s.accepted = new bool[](c.handoffs.length);
        s.framePre = new uint256[](c.assets.length);
        s.fees = new uint256[](c.rules.length);
        uint256 maxGrants = n + c.handoffs.length;
        s.grantedToken = new address[](maxGrants);
        s.grantedSpender = new address[](maxGrants);
        for (uint256 i; i < terms; ++i) {
            Term memory t = c.terms[i];
            uint8 op = t.op;
            if (op == Codes.OP_DELTA || op == Codes.OP_POST_VIEW) {
                s.post[i] = true;
            } else if (op == Codes.OP_CONSUMED_VALUE) {
                s.scoped[i] = true;
            } else if (op >= Codes.OP_ADD && op <= Codes.OP_MUL_BPS) {
                bool binary = op != Codes.OP_MUL_BPS;
                s.post[i] = s.post[t.a] || (binary && s.post[t.b]);
                s.scoped[i] = s.scoped[t.a] || (binary && s.scoped[t.b]);
            }
        }
    }

    /// Pre-state: input presence and threshold, DELTA baselines, and the frame's baselines.
    function _snapshot(Constraints memory c, Run memory run, State memory s) private view {
        InputSet memory inputs = c.inputs;
        uint256 present;
        for (uint256 p; p < inputs.assets.length; ++p) {
            uint256 held = _held(c.assets[inputs.assets[p]], run.holder);
            // Cached for DRAIN, which consumes exactly this pre-state balance.
            s.consumed[p] = held;
            if (held >= inputs.minimums[p] && (inputs.minimums[p] > 0 || held > 0)) {
                s.present[p] = true;
                ++present;
            }
        }
        if (present < inputs.threshold) {
            revert NotExecutable();
        }
        for (uint256 i; i < c.terms.length; ++i) {
            Term memory t = c.terms[i];
            if (t.op == Codes.OP_DELTA) {
                s.deltaPre[i] = _balanceOf(c.assets[t.a], _account(c, run, t.b));
            }
        }
        if (c.frame == Codes.FRAME_STRICT) {
            for (uint256 i; i < c.assets.length; ++i) {
                if (_local(c.assets[i])) {
                    s.framePre[i] = _balanceOf(c.assets[i], run.holder);
                }
            }
        }
    }

    function _selectRules(Constraints memory c, Run memory run, State memory s) private view {
        bool any;
        for (uint256 r; r < c.rules.length; ++r) {
            Rule memory rule = c.rules[r];
            bool on;
            if (rule.when.length == 0) {
                on = rule.inputs.length == 0;
                for (uint256 j; j < rule.inputs.length && !on; ++j) {
                    on = s.present[rule.inputs[j]];
                }
            } else {
                on = _groups(c, run, s, rule.when, r);
            }
            if (on) {
                s.active[r] = true;
                any = true;
                if (c.matching == Codes.MATCH_FIRST) {
                    break;
                }
            }
        }
        if (!any) {
            revert NotExecutable();
        }
        // _snapshot left each input's pre-state balance in consumed; only active rules' present
        // inputs are consumed, all of it under DRAIN, exactly the minimum under EXACT.
        uint256[] memory held = s.consumed;
        s.consumed = new uint256[](held.length);
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r]) {
                continue;
            }
            s.scopedMemo[r] = new int256[](c.terms.length);
            s.scopedKnown[r] = new bool[](c.terms.length);
            Rule memory rule = c.rules[r];
            for (uint256 j; j < rule.inputs.length; ++j) {
                uint16 p = rule.inputs[j];
                if (s.present[p]) {
                    s.consumed[p] = rule.consume == Codes.DRAIN ? held[p] : c.inputs.minimums[p];
                }
            }
        }
    }

    /// Runtime half of the custody test: every OR group of a keeper-routed active rule's outcome
    /// needs a bound whose pre-state value is positive (non-negative for a strict bound). A spend
    /// cap (a negative floor) bounds nothing the keeper delivers.
    function _positive(Constraints memory c, Run memory run, State memory s) private view returns (bool) {
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r] || c.rules[r].route.length > 0) {
                continue;
            }
            Rule memory rule = c.rules[r];
            uint256 seen;
            uint256 bounded;
            for (uint256 j; j < rule.then.length; ++j) {
                Predicate memory p = c.predicates[rule.then[j]];
                uint256 bit = uint256(1) << p.group;
                seen |= bit;
                if (p.cmp == Codes.CMP_ACCEPTED) {
                    bounded |= bit;
                } else if ((p.cmp == Codes.CMP_GTE || p.cmp == Codes.CMP_EQ || p.cmp == Codes.CMP_GT) && s.post[p.lhs])
                {
                    int256 floor = _eval(c, run, s, p.rhs, r);
                    if (floor > 0 || (p.cmp == Codes.CMP_GT && floor == 0)) {
                        bounded |= bit;
                    }
                }
            }
            if (seen == 0 || seen != bounded) {
                return false;
            }
        }
        return true;
    }

    function _payFees(Constraints memory c, Run memory run, State memory s) private {
        for (uint256 r; r < c.rules.length; ++r) {
            Rule memory rule = c.rules[r];
            if (!s.active[r] || rule.fee == Codes.NONE) {
                continue;
            }
            int256 fee = _eval(c, run, s, rule.fee, r);
            if (fee <= 0 || run.caller == address(0)) {
                continue; // a non-positive fee is skipped, never inverted
            }
            s.fees[r] = uint256(fee);
            _send(c.assets[rule.feeAsset], run, run.caller, uint256(fee));
        }
    }

    function _routes(Constraints memory c, Run memory run, State memory s) private {
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r]) {
                continue;
            }
            bytes memory data = _ruleData(c.rules[r], run, r);
            if (data.length == 0) {
                continue; // handoff-only rule: the inputs go straight to its handoffs
            }
            (Token[] memory tokens, uint256 value) = _ruleTokens(c, run, s, r);
            if (tokens.length == 0) {
                continue;
            }
            address router = s.router;
            if (router == address(0)) {
                revert NoRouter();
            }
            for (uint256 i; i < tokens.length; ++i) {
                if (tokens[i].tokenType != TokenType.Native) {
                    _grantToken(tokens[i], router, s);
                }
            }
            if (tokens.length == 1) {
                IEnsoRouter(router).routeSingle{ value: value }(tokens[0], data);
            } else {
                IEnsoRouter(router).routeMulti{ value: value }(tokens, data);
            }
            for (uint256 i; i < tokens.length; ++i) {
                if (tokens[i].tokenType != TokenType.Native) {
                    _revokeToken(tokens[i], router);
                }
            }
        }
    }

    /// The rule's present inputs with the amounts the route spends: what the rule consumes, less
    /// the rule fee paid in the same asset. A router pulls them from the holder first.
    function _ruleTokens(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint256 r
    )
        private
        returns (Token[] memory tokens, uint256 value)
    {
        Rule memory rule = c.rules[r];
        tokens = new Token[](rule.inputs.length);
        uint256 count;
        for (uint256 j; j < rule.inputs.length; ++j) {
            uint16 p = rule.inputs[j];
            if (!s.present[p]) {
                continue;
            }
            uint16 assetIndex = c.inputs.assets[p];
            Asset memory a = c.assets[assetIndex];
            uint256 amount = s.consumed[p];
            if (rule.feeAsset == assetIndex) {
                amount = amount > s.fees[r] ? amount - s.fees[r] : 0;
            }
            if (amount == 0) {
                continue;
            }
            if (run.pull) {
                _pull(a, run.holder, amount);
            }
            if (a.kind == Codes.NATIVE) {
                value = amount;
            }
            tokens[count++] = _token(a, amount);
        }
        assembly ("memory-safe") {
            mstore(tokens, count)
        }
    }

    function _handoffs(Constraints memory c, Run memory run, State memory s) private {
        bool nativeInputs;
        for (uint256 p; p < c.inputs.assets.length; ++p) {
            nativeInputs = nativeInputs || c.assets[c.inputs.assets[p]].kind == Codes.NATIVE;
        }
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r]) {
                continue;
            }
            Rule memory rule = c.rules[r];
            for (uint256 j; j < rule.then.length; ++j) {
                Predicate memory p = c.predicates[rule.then[j]];
                if (p.cmp != Codes.CMP_ACCEPTED || s.accepted[p.lhs]) {
                    continue;
                }
                _handoff(c, run, s, p.lhs, r, nativeInputs);
            }
        }
    }

    function _handoff(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint16 index,
        uint256 r,
        bool nativeInputs
    )
        private
    {
        Handoff memory h = c.handoffs[index];
        Source memory source = c.sources[h.source];
        IIntentGuardian guardian = IIntentGuardian(source.target);
        if (uint8(guardian.level()) != abi.decode(source.config, (uint8))) {
            revert WrongLevel(index);
        }
        Asset memory input = c.assets[h.input];
        // A handoff-only rule hands over exactly what it consumes; after a route, the handoff takes
        // whatever the route left in the handed asset.
        (bool direct, uint256 amount) = _directAmount(c, run, s, h.input, r);
        if (direct) {
            if (run.pull && amount > 0) {
                _pull(input, run.holder, amount);
            }
        } else {
            amount = _balanceOf(input, address(this));
        }
        Obligation memory obligation = Obligation({
            chainId: h.chainId,
            method: h.method,
            recipient: h.recipient,
            refund: h.refund,
            token: c.assets[h.asset].token,
            minAmount: _nonNegative(_eval(c, run, s, h.minAmount, r)),
            deadline: uint64(_nonNegative(_eval(c, run, s, h.deadline, r)))
        });
        // Native forwarded beyond a native input is the keeper's messaging-fee money.
        uint256 value = input.kind == Codes.NATIVE ? amount : (nativeInputs ? 0 : address(this).balance);
        Token memory token = _token(input, amount);
        if (input.kind != Codes.NATIVE) {
            _grantToken(token, address(guardian), s);
        }
        guardian.accept{ value: value }(
            run.id, token, amount, obligation, index < run.contexts.length ? run.contexts[index] : bytes("")
        );
        if (input.kind != Codes.NATIVE) {
            _revokeToken(token, address(guardian));
        }
        s.accepted[index] = true;
    }

    /// Whether the handoff's asset is a present input of a rule that runs no route, and if so the
    /// amount the rule hands over: what it consumes, less its fee in the same asset.
    function _directAmount(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint16 assetIndex,
        uint256 r
    )
        private
        pure
        returns (bool direct, uint256 amount)
    {
        Rule memory rule = c.rules[r];
        if (_ruleData(rule, run, r).length > 0) {
            return (false, 0);
        }
        for (uint256 j; j < rule.inputs.length; ++j) {
            uint16 p = rule.inputs[j];
            if (s.present[p] && c.inputs.assets[p] == assetIndex) {
                direct = true;
                amount += s.consumed[p];
            }
        }
        if (direct && rule.feeAsset == assetIndex) {
            amount = amount > s.fees[r] ? amount - s.fees[r] : 0;
        }
    }

    function _ruleData(Rule memory rule, Run memory run, uint256 r) private pure returns (bytes memory) {
        if (rule.route.length > 0) {
            return rule.route;
        }
        return r < run.routes.length ? run.routes[r] : bytes("");
    }

    function _outcomes(Constraints memory c, Run memory run, State memory s) private {
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r]) {
                continue;
            }
            Rule memory rule = c.rules[r];
            if (rule.then.length == 0) {
                continue;
            }
            // The lowest group whose comparisons and handoffs hold; its counter writes then apply.
            uint256 seen;
            uint256 failed;
            for (uint256 j; j < rule.then.length; ++j) {
                Predicate memory p = c.predicates[rule.then[j]];
                uint256 bit = uint256(1) << p.group;
                seen |= bit;
                if (p.cmp == Codes.CMP_CONSUMED_WITHIN || failed & bit != 0) {
                    continue;
                }
                bool ok = p.cmp == Codes.CMP_ACCEPTED ? s.accepted[p.lhs] : _compare(c, run, s, p, r);
                if (!ok) {
                    failed |= bit;
                }
            }
            uint256 passing = seen & ~failed;
            if (passing == 0) {
                revert PredicateFailed(uint16(r));
            }
            uint256 chosen = passing & (~passing + 1); // lowest set bit
            for (uint256 j; j < rule.then.length; ++j) {
                Predicate memory p = c.predicates[rule.then[j]];
                if (p.cmp == Codes.CMP_CONSUMED_WITHIN && (uint256(1) << p.group) == chosen) {
                    _consume(c, run, s, p.lhs, r);
                }
            }
        }
    }

    function _consume(Constraints memory c, Run memory run, State memory s, uint16 index, uint256 r) private {
        Consume memory k = c.consumes[index];
        uint256 amount = _nonNegative(_eval(c, run, s, k.amount, r));
        // Reverts with CapExceeded when the window's cap would be passed.
        IIntentCounter(c.sources[k.source].target).consume(run.record, k.key, amount, k.cap, k.period);
    }

    /// Strict frame over the holder's named assets on this chain: nothing decreases beyond what the
    /// active rules consume and pay, and no approval granted during execution remains.
    function _frame(Constraints memory c, Run memory run, State memory s) private view {
        uint256[] memory permitted = new uint256[](c.assets.length);
        for (uint256 r; r < c.rules.length; ++r) {
            if (!s.active[r]) {
                continue;
            }
            Rule memory rule = c.rules[r];
            for (uint256 j; j < rule.inputs.length; ++j) {
                uint16 p = rule.inputs[j];
                permitted[c.inputs.assets[p]] += s.consumed[p];
            }
            // A fee in an input asset is already inside what the rule consumes.
            if (rule.fee != Codes.NONE && !_isRuleInput(c, rule, rule.feeAsset)) {
                permitted[rule.feeAsset] += s.fees[r];
            }
        }
        for (uint256 i; i < c.assets.length; ++i) {
            Asset memory a = c.assets[i];
            if (!_local(a) || (a.kind == Codes.NATIVE && !run.pull)) {
                // Native at an ephemeral holder also carries the keeper's messaging-fee money.
                continue;
            }
            uint256 balance = _balanceOf(a, run.holder);
            if (balance + permitted[i] < s.framePre[i]) {
                revert FrameViolation(uint16(i));
            }
        }
        for (uint256 i; i < s.granted; ++i) {
            address token = s.grantedToken[i];
            if (token != address(0) && IERC20(token).allowance(address(this), s.grantedSpender[i]) != 0) {
                revert ApprovalLeft(token, s.grantedSpender[i]);
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Terms
    // ---------------------------------------------------------------------------------------------

    function _groups(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint16[] memory list,
        uint256 r
    )
        private
        view
        returns (bool)
    {
        uint256 seen;
        uint256 failed;
        for (uint256 j; j < list.length; ++j) {
            Predicate memory p = c.predicates[list[j]];
            uint256 bit = uint256(1) << p.group;
            seen |= bit;
            if (failed & bit == 0 && !_compare(c, run, s, p, r)) {
                failed |= bit;
            }
        }
        return seen & ~failed != 0;
    }

    function _compare(
        Constraints memory c,
        Run memory run,
        State memory s,
        Predicate memory p,
        uint256 r
    )
        private
        view
        returns (bool)
    {
        return _cmp(p.cmp, _eval(c, run, s, p.lhs, r), _eval(c, run, s, p.rhs, r));
    }

    function _cmp(uint8 cmp, int256 lhs, int256 rhs) private pure returns (bool) {
        if (cmp == Codes.CMP_GTE) {
            return lhs >= rhs;
        } else if (cmp == Codes.CMP_GT) {
            return lhs > rhs;
        } else if (cmp == Codes.CMP_LTE) {
            return lhs <= rhs;
        } else if (cmp == Codes.CMP_LT) {
            return lhs < rhs;
        }
        return lhs == rhs;
    }

    /// Evaluate term `index` in rule `r`'s scope, memoized. Operands always precede their term.
    function _eval(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint16 index,
        uint256 r
    )
        private
        view
        returns (int256 value)
    {
        bool scoped = s.scoped[index];
        if (scoped ? s.scopedKnown[r][index] : s.known[index]) {
            return scoped ? s.scopedMemo[r][index] : s.memo[index];
        }
        // Post-state terms are only final once execution is done; never cache them early.
        if (s.post[index] && !s.postPhase) {
            revert NotExecutable();
        }
        Term memory t = c.terms[index];
        uint8 op = t.op;
        if (op == Codes.OP_CONST) {
            value = _signed(t.value);
        } else if (op == Codes.OP_NOW) {
            value = _signed(block.timestamp);
        } else if (op == Codes.OP_BALANCE) {
            value = _signed(_balanceOf(c.assets[t.a], _account(c, run, t.b)));
        } else if (op == Codes.OP_DELTA) {
            value = _signed(_balanceOf(c.assets[t.a], _account(c, run, t.b))) - _signed(s.deltaPre[index]);
        } else if (op == Codes.OP_PRE_VIEW || op == Codes.OP_POST_VIEW) {
            value = _signed(_view(c.views[t.a], t.a));
        } else if (op == Codes.OP_SOURCE) {
            value = _signed(_source(c, run, t));
        } else if (op == Codes.OP_CONSUMED) {
            value = _signed(_consumedOf(c, s, t.a));
        } else if (op == Codes.OP_CONSUMED_VALUE) {
            value = _signed(_consumedValue(c, run, s, t.a, r));
        } else {
            int256 a = _eval(c, run, s, t.a, r);
            if (op == Codes.OP_MUL_BPS) {
                value = a * _signed(t.value) / 10_000;
            } else {
                int256 b = _eval(c, run, s, t.b, r);
                if (op == Codes.OP_ADD) {
                    value = a + b;
                } else if (op == Codes.OP_SUB) {
                    value = a - b;
                } else if (op == Codes.OP_MUL) {
                    value = a * b / 1e18;
                } else {
                    if (b == 0) {
                        revert DivisionByZero();
                    }
                    value = a * 1e18 / b;
                }
            }
        }
        if (scoped) {
            s.scopedMemo[r][index] = value;
            s.scopedKnown[r][index] = true;
        } else {
            s.memo[index] = value;
            s.known[index] = true;
        }
    }

    function _consumedOf(Constraints memory c, State memory s, uint16 assetIndex) private pure returns (uint256 sum) {
        for (uint256 p; p < c.inputs.assets.length; ++p) {
            if (c.inputs.assets[p] == assetIndex) {
                sum += s.consumed[p];
            }
        }
    }

    function _consumedValue(
        Constraints memory c,
        Run memory run,
        State memory s,
        uint16 quote,
        uint256 r
    )
        private
        view
        returns (uint256 sum)
    {
        Rule memory rule = c.rules[r];
        for (uint256 j; j < rule.inputs.length; ++j) {
            uint16 p = rule.inputs[j];
            uint256 amount = s.consumed[p];
            if (amount == 0) {
                continue;
            }
            uint16 price = c.inputs.prices[p];
            if (price == Codes.NONE) {
                revert NotExecutable(); // CONSUMED_VALUE needs a price for every input it sums
            }
            uint256 rate = _oracle(c, run, price, c.assets[c.inputs.assets[p]].token, c.assets[quote].token);
            sum += amount * rate / 1e18;
        }
    }

    function _source(Constraints memory c, Run memory run, Term memory t) private view returns (uint256) {
        Source memory source = c.sources[t.a];
        if (source.kind == Codes.ORACLE) {
            return _oracle(c, run, t.a, c.assets[t.b].token, c.assets[t.value].token);
        }
        // COUNTER: usage so far, as written by this contract.
        return IIntentCounter(source.target).used(address(this), run.record, bytes32(t.data), uint64(t.value));
    }

    function _oracle(
        Constraints memory c,
        Run memory run,
        uint16 index,
        address base,
        address quote
    )
        private
        view
        returns (uint256 value)
    {
        Source memory source = c.sources[index];
        uint64 asOf;
        (value, asOf) = IIntentOracle(source.target).read(run.id, base, quote, "");
        uint32 staleness = abi.decode(source.config, (uint32));
        // forge-lint: disable-next-line(block-timestamp)
        if (asOf > block.timestamp || block.timestamp - asOf > staleness) {
            revert Stale(index);
        }
    }

    function _view(View memory v, uint16 index) private view returns (uint256 word) {
        (bool ok, bytes memory ret) = v.target.staticcall(bytes.concat(v.selector, v.args));
        uint256 offset = uint256(v.word) * 32;
        if (!ok || ret.length < offset + 32) {
            revert ViewFailed(index);
        }
        assembly ("memory-safe") {
            word := mload(add(add(ret, 0x20), offset))
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Assets
    // ---------------------------------------------------------------------------------------------

    function _account(Constraints memory c, Run memory run, uint16 index) private pure returns (address) {
        if (index == Codes.HOLDER) {
            return run.holder;
        }
        if (index == Codes.OWNER) {
            return run.owner;
        }
        return c.accounts[index - 2];
    }

    function _local(Asset memory a) private view returns (bool) {
        return a.chainId == block.chainid || a.chainId == 0;
    }

    /// Input presence: ERC721 counts the committed id, every other kind its balance.
    function _held(Asset memory a, address account) private view returns (uint256) {
        if (a.kind == Codes.ERC721) {
            return IERC721(a.token).ownerOf(a.id) == account ? 1 : 0;
        }
        return _balanceOf(a, account);
    }

    /// Balances for terms and the frame: ERC721 counts the collection, as outcomes may be freshly
    /// minted ids that can't be named in advance.
    function _balanceOf(Asset memory a, address account) private view returns (uint256) {
        uint8 kind = a.kind;
        if (kind == Codes.NATIVE) {
            return account.balance;
        } else if (kind == Codes.ERC1155) {
            return IERC1155(a.token).balanceOf(account, a.id);
        }
        return IERC20(a.token).balanceOf(account);
    }

    function _token(Asset memory a, uint256 amount) private pure returns (Token memory) {
        uint8 kind = a.kind;
        if (kind == Codes.NATIVE) {
            return Token({ tokenType: TokenType.Native, data: abi.encode(amount) });
        } else if (kind == Codes.ERC721) {
            return Token({ tokenType: TokenType.ERC721, data: abi.encode(a.token, a.id) });
        } else if (kind == Codes.ERC1155) {
            return Token({ tokenType: TokenType.ERC1155, data: abi.encode(a.token, a.id, amount) });
        }
        return Token({ tokenType: TokenType.ERC20, data: abi.encode(a.token, amount) });
    }

    function _send(Asset memory a, Run memory run, address to, uint256 amount) private {
        uint8 kind = a.kind;
        if (kind == Codes.NATIVE) {
            if (run.pull) {
                revert UnsupportedAsset(0); // nothing native can be pulled from a wallet
            }
            (bool ok,) = to.call{ value: amount }("");
            if (!ok) {
                revert NotExecutable();
            }
        } else if (kind == Codes.ERC721) {
            IERC721(a.token).transferFrom(run.pull ? run.holder : address(this), to, a.id);
        } else if (kind == Codes.ERC1155) {
            IERC1155(a.token).safeTransferFrom(run.pull ? run.holder : address(this), to, a.id, amount, "");
        } else if (run.pull) {
            IERC20(a.token).safeTransferFrom(run.holder, to, amount);
        } else {
            IERC20(a.token).safeTransfer(to, amount);
        }
    }

    function _pull(Asset memory a, address from, uint256 amount) private {
        uint8 kind = a.kind;
        if (kind == Codes.NATIVE) {
            revert UnsupportedAsset(0);
        } else if (kind == Codes.ERC721) {
            IERC721(a.token).transferFrom(from, address(this), a.id);
        } else if (kind == Codes.ERC1155) {
            IERC1155(a.token).safeTransferFrom(from, address(this), a.id, amount, "");
        } else {
            IERC20(a.token).safeTransferFrom(from, address(this), amount);
        }
    }

    function _grant(Asset memory a, address spender, uint256 amount) private {
        _grantToken(_token(a, amount), spender, _noTracking());
    }

    function _noTracking() private pure returns (State memory s) {
        s.grantedToken = new address[](0);
    }

    function _grantToken(Token memory token, address spender, State memory s) private {
        TokenType kind = token.tokenType;
        if (kind == TokenType.ERC20) {
            (address erc20, uint256 amount) = abi.decode(token.data, (address, uint256));
            IERC20(erc20).forceApprove(spender, amount);
            if (s.granted < s.grantedToken.length) {
                s.grantedToken[s.granted] = erc20;
                s.grantedSpender[s.granted] = spender;
                ++s.granted;
            }
        } else if (kind == TokenType.ERC721) {
            (address erc721, uint256 id) = abi.decode(token.data, (address, uint256));
            IERC721(erc721).approve(spender, id);
        } else if (kind == TokenType.ERC1155) {
            (address erc1155,,) = abi.decode(token.data, (address, uint256, uint256));
            IERC1155(erc1155).setApprovalForAll(spender, true);
        }
    }

    /// Revoke after the call. Approvals live in the token and outlive the account, so none may
    /// remain; an ERC721 that has moved can't be revoked and needs no revoke.
    function _revokeToken(Token memory token, address spender) private {
        TokenType kind = token.tokenType;
        if (kind == TokenType.ERC20) {
            (address erc20,) = abi.decode(token.data, (address, uint256));
            IERC20(erc20).forceApprove(spender, 0);
        } else if (kind == TokenType.ERC721) {
            (address erc721, uint256 id) = abi.decode(token.data, (address, uint256));
            if (IERC721(erc721).ownerOf(id) == address(this)) {
                IERC721(erc721).approve(address(0), id);
            }
        } else if (kind == TokenType.ERC1155) {
            (address erc1155,,) = abi.decode(token.data, (address, uint256, uint256));
            IERC1155(erc1155).setApprovalForAll(spender, false);
        }
    }

    function _isRuleInput(Constraints memory c, Rule memory rule, uint16 assetIndex) private pure returns (bool) {
        for (uint256 j; j < rule.inputs.length; ++j) {
            if (c.inputs.assets[rule.inputs[j]] == assetIndex) {
                return true;
            }
        }
        return false;
    }

    function _signed(uint256 value) private pure returns (int256) {
        if (value > uint256(type(int256).max)) {
            revert Overflow();
        }
        return int256(value);
    }

    function _nonNegative(int256 value) private pure returns (uint256) {
        return value > 0 ? uint256(value) : 0;
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {
    Codes,
    Constraints,
    Intent,
    Pattern,
    Predicate,
    Source,
    Term,
    View
} from "../../../../../src/interfaces/IIntent.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// Intents this version refuses: attestation, trace patterns, and keeper routes nothing checks.
/// Each is refunded at once, by anyone, paying the refund fee.
contract EphemeralIntentExecutor_Rejected_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;
    uint256 internal constant REFUND_FEE = 0.5 ether;

    function _swapConstraints() internal view returns (Constraints memory) {
        return
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, REFUND_FEE, Codes.DRAIN);
    }

    /// Statically refused intents refund for anyone: a stranger, not the keeper.
    function _assertRefunded(Constraints memory c, uint8 status) internal {
        _assertRefunded(c, status, s_stranger);
    }

    function _assertRefunded(Constraints memory c, uint8 status, address caller) internal {
        Intent memory intent = _intent(c, s_user, s_keeper);
        assertEq(IntentEvaluator.check(intent), status, "status");
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);

        _run(caller, root, _withRoute(_execution(intent), hex"c0ffee"));

        assertEq(s_tokenIn.balanceOf(caller), REFUND_FEE, "refund fee to the caller");
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT - REFUND_FEE, "the rest to the owner");
        assertEq(s_tokenIn.balanceOf(at), 0, "nothing left");
        assertEq(s_router.calls(), 0, "nothing routed");
    }

    function test_AttestedPredicate_Refunds() external {
        Constraints memory c = _swapConstraints();
        c.predicates[0].enforce = Codes.ENFORCE_ATTESTED;
        _assertRefunded(c, IntentEvaluator.UNSUPPORTED);
    }

    function test_BothPredicate_Refunds() external {
        Constraints memory c = _swapConstraints();
        c.predicates[0].enforce = Codes.BOTH;
        _assertRefunded(c, IntentEvaluator.UNSUPPORTED);
    }

    function test_AttestedSource_Refunds() external {
        Constraints memory c = _swapConstraints();
        c.sources = new Source[](1);
        c.sources[0] = Source({ kind: Codes.ATTESTED, target: address(1), config: "" });
        _assertRefunded(c, IntentEvaluator.UNSUPPORTED);
    }

    function test_Pattern_Refunds() external {
        Constraints memory c = _swapConstraints();
        c.patterns = new Pattern[](1);
        _assertRefunded(c, IntentEvaluator.UNSUPPORTED);
    }

    function test_KeeperRouteWithoutOutcome_Refunds() external {
        Constraints memory c = _swapConstraints();
        c.rules[0].then = new uint16[](0);
        _assertRefunded(c, IntentEvaluator.CUSTODIAL);
    }

    function test_KeeperRouteWithOnlyAPreStateCheck_Refunds() external {
        Constraints memory c = _swapConstraints();
        // CONSUMED >= rate: a comparison, but over nothing the keeper delivers.
        c.predicates[0] = _pred(Codes.CMP_GTE, 1, 2);
        _assertRefunded(c, IntentEvaluator.CUSTODIAL);
    }

    function test_UnboundedOrGroup_Refunds() external {
        Constraints memory c = _swapConstraints();
        // Group 1 holds only a pre-state comparison, so the keeper could satisfy the rule by it alone.
        c.predicates = _twoPredicates(c);
        c.rules[0].then = _two(0, 1);
        _assertRefunded(c, IntentEvaluator.CUSTODIAL);
    }

    /// A spend cap passes the static test (a lower bound on a delta) but its floor is negative at
    /// execution, so it bounds nothing the keeper delivers. Found in the execute arm, after the
    /// keeper gate, so the keeper's attempt is what refunds it. The refusal depends on what is at
    /// the address, which a caller can steer, so the refund pays no fee.
    function test_SpendCapOnly_RefundsAtExecution() external {
        Constraints memory c = _swapConstraints();
        // floor = 0 - consumed: delta(out, owner) >= -consumed
        c.terms[2] = _term(Codes.OP_CONST, 0, 0, 0);
        c.terms[3] = _term(Codes.OP_SUB, 2, 1, 0);
        Intent memory intent = _intent(c, s_user, s_keeper);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "status");
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));

        assertEq(s_tokenIn.balanceOf(s_keeper), 0, "no refund fee");
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "all to the owner");
        assertEq(s_tokenIn.balanceOf(at), 0, "nothing left");
        assertEq(s_router.calls(), 0, "nothing routed");
    }

    /// A post-state comparison beside a bound, both sides post-state, isn't a candidate bound at
    /// run time either: the honest route runs and the floor still binds.
    function test_PostAgainstPost_BesideABound_Executes() external {
        Constraints memory c = _swapConstraints();
        c.views = new View[](1);
        c.views[0] = View({
            target: address(s_tokenOut), selector: IERC20.balanceOf.selector, args: abi.encode(s_stranger), word: 0
        });
        Term[] memory terms = new Term[](6);
        for (uint256 i; i < 5; ++i) {
            terms[i] = c.terms[i];
        }
        terms[5] = _term(Codes.OP_POST_VIEW, 0, 0, 0);
        c.terms = terms;
        Predicate[] memory predicates = new Predicate[](2);
        predicates[0] = c.predicates[0];
        predicates[1] = _pred(Codes.CMP_GTE, 0, 5); // delta(out, owner) >= post(stranger's out)
        c.predicates = predicates;
        c.rules[0].then = _two(0, 1);
        Intent memory intent = _intent(c, s_user, s_keeper);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "status");
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 2 * DEPOSIT, s_user);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenOut.balanceOf(s_user), 2 * DEPOSIT, "delivered");
    }

    function _twoPredicates(Constraints memory c) internal pure returns (Predicate[] memory list) {
        list = new Predicate[](2);
        list[0] = c.predicates[0];
        list[1] = _pred(Codes.CMP_GTE, 1, 2);
        list[1].group = 1;
    }
}

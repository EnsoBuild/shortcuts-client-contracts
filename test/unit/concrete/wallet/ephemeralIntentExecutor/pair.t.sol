// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import {
    Asset,
    Codes,
    Constraints,
    Fee,
    Input,
    Intent,
    Predicate,
    Rule,
    Term
} from "../../../../../src/interfaces/IIntent.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

/// Rules that need two inputs at once, like a deposit into a liquidity pool: the rule runs only
/// when both are present, and its route receives both.
contract EphemeralIntentExecutor_Pair_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant AMOUNT_A = 100 ether;
    uint256 internal constant AMOUNT_B = 50 ether;
    uint256 internal constant LP_FLOOR = 10 ether;
    uint256 internal constant FEE = 1 ether;

    MockERC20 internal s_tokenB;

    function setUp() public override {
        super.setUp();
        s_tokenB = new MockERC20("TokenB", "TB");
        vm.label(address(s_tokenB), "TokenB");
    }

    /// Assets: 0 tokenIn (A), 1 tokenB, 2 tokenOut (the LP token). One keeper-routed rule over both
    /// inputs, threshold 2, draining both; outcome: at least LP_FLOOR LP to the owner.
    ///   terms: 0 DELTA(LP, owner), 1 CONST floor
    function _pairConstraints() internal view returns (Constraints memory c) {
        c = _constraints(address(s_router));
        c.assets = new Asset[](3);
        c.assets[0] = _erc20(address(s_tokenIn));
        c.assets[1] = _erc20(address(s_tokenB));
        c.assets[2] = _erc20(address(s_tokenOut));
        c.terms = new Term[](2);
        c.terms[0] = _term(Codes.OP_DELTA, 2, Codes.OWNER, 0);
        c.terms[1] = _term(Codes.OP_CONST, 0, 0, LP_FLOOR);
        c.predicates = new Predicate[](1);
        c.predicates[0] = _pred(Codes.CMP_GTE, 0, 1);
        c.rules = new Rule[](1);
        c.rules[0] = _rule(_inputs(0, AMOUNT_A, 1, AMOUNT_B), _one(0), NONE, NONE, Codes.DRAIN);
        c.rules[0].threshold = 2;
    }

    function _fundB(bytes32 root, uint256 amount) internal {
        s_tokenB.mint(s_factory.getAddress(root), amount);
    }

    function test_BothPresent_RoutesBothTogether() external {
        Intent memory intent = _intent(_pairConstraints(), s_user, s_keeper);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "status");
        bytes32 root = _root(intent);
        address at = _fund(root, AMOUNT_A);
        _fundB(root, AMOUNT_B);
        s_router.addOut(address(s_tokenOut), LP_FLOOR, s_user);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));

        Token[] memory tokens = s_router.lastTokens();
        assertEq(tokens.length, 2, "one call with both inputs");
        assertEq(uint8(tokens[0].tokenType), uint8(TokenType.ERC20), "ERC20");
        assertEq(tokens[0].data, abi.encode(address(s_tokenIn), AMOUNT_A), "token A");
        assertEq(tokens[1].data, abi.encode(address(s_tokenB), AMOUNT_B), "token B");
        assertEq(s_tokenIn.balanceOf(at), 0, "A drained");
        assertEq(s_tokenB.balanceOf(at), 0, "B drained");
        assertEq(s_tokenOut.balanceOf(s_user), LP_FLOOR, "LP delivered");
        assertEq(s_tokenB.allowance(at, address(s_router)), 0, "approval revoked");
    }

    function test_OneMissing_DoesNotRun() external {
        Intent memory intent = _intent(_pairConstraints(), s_user, s_keeper);
        bytes32 root = _root(intent);
        address at = _fund(root, AMOUNT_A);
        _fundB(root, AMOUNT_B - 1); // below B's minimum: absent
        s_router.addOut(address(s_tokenOut), LP_FLOOR, s_user);

        vm.expectRevert(IntentEvaluator.NotExecutable.selector);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenIn.balanceOf(at), AMOUNT_A, "A waits for B");
    }

    function test_AfterDeadline_RefundsBothInputsWithoutAFee() external {
        Intent memory intent = _intent(_pairConstraints(), s_user, s_keeper);
        bytes32 root = _root(intent);
        address at = _fund(root, AMOUNT_A);
        _fundB(root, 1 ether); // never completed the pair
        vm.warp(intent.deadline + 1);

        _run(s_stranger, root, _execution(intent));

        assertEq(s_tokenIn.balanceOf(s_user), AMOUNT_A, "A back to the owner");
        assertEq(s_tokenB.balanceOf(s_user), 1 ether, "B back to the owner");
        assertEq(s_tokenIn.balanceOf(s_stranger) + s_tokenB.balanceOf(s_stranger), 0, "no refunds listed: no fee");
        assertEq(at.code.length, 0, "terminated");
    }

    function test_ThresholdOutOfRange_IsMalformed() external view {
        Constraints memory c = _pairConstraints();
        c.rules[0].threshold = 3;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "above inputs");
        c.rules[0].threshold = 0;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "zero with inputs");
    }

    function test_SameAssetTwiceInARule_IsMalformed() external view {
        Constraints memory c = _pairConstraints();
        c.rules[0].inputs[1].asset = 0;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "status");
    }

    /// Under ALL matching two rules may not consume the same asset; under FIRST only one runs.
    function test_SharedInputAcrossRules_OnlyUnderFirstMatch() external view {
        Constraints memory c = _pairConstraints();
        c.rules = new Rule[](2);
        c.rules[0] = _rule(_inputs(0, AMOUNT_A, 1, AMOUNT_B), _one(0), NONE, NONE, Codes.DRAIN);
        c.rules[0].threshold = 2;
        c.rules[1] = _rule(_input(0, AMOUNT_A), _one(0), NONE, NONE, Codes.DRAIN);
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "all");
        c.matching = Codes.MATCH_FIRST;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.OK, "first");
    }

    /// Either token alone, with a 1-token fee in whichever arrived: candidates A then B.
    ///   terms: 0 DELTA(LP, owner), 1 CONST floor, 2 CONST fee
    function _eitherConstraints() internal view returns (Constraints memory c) {
        c = _pairConstraints();
        c.terms = new Term[](3);
        c.terms[0] = _term(Codes.OP_DELTA, 2, Codes.OWNER, 0);
        c.terms[1] = _term(Codes.OP_CONST, 0, 0, LP_FLOOR);
        c.terms[2] = _term(Codes.OP_CONST, 0, 0, FEE);
        c.rules[0].threshold = 1;
        c.rules[0].fees = new Fee[](2);
        c.rules[0].fees[0] = Fee({ asset: 0, amount: 2 });
        c.rules[0].fees[1] = Fee({ asset: 1, amount: 2 });
    }

    function _runEither(Constraints memory c, uint256 a, uint256 b) internal returns (address at) {
        Intent memory intent = _intent(c, s_user, s_keeper);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "status");
        bytes32 root = _root(intent);
        at = s_factory.getAddress(root);
        if (a > 0) {
            _fund(root, a);
        }
        if (b > 0) {
            _fundB(root, b);
        }
        s_router.addOut(address(s_tokenOut), LP_FLOOR, s_user);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
    }

    function test_Fee_PaidInTheFirstPresentCandidate() external {
        _runEither(_eitherConstraints(), AMOUNT_A, AMOUNT_B);
        assertEq(s_tokenIn.balanceOf(s_keeper), FEE, "fee in A, the first candidate");
        assertEq(s_tokenB.balanceOf(s_keeper), 0, "nothing in B");
        Token[] memory tokens = s_router.lastTokens();
        assertEq(tokens[0].data, abi.encode(address(s_tokenIn), AMOUNT_A - FEE), "A less the fee");
        assertEq(tokens[1].data, abi.encode(address(s_tokenB), AMOUNT_B), "all of B");
    }

    function test_Fee_FallsBackWhenTheFirstIsAbsent() external {
        address at = _runEither(_eitherConstraints(), 0, AMOUNT_B);
        assertEq(s_tokenB.balanceOf(s_keeper), FEE, "fee in B");
        assertEq(s_tokenIn.balanceOf(s_keeper), 0, "nothing in A");
        assertEq(s_tokenB.balanceOf(at), 0, "B drained");
        assertEq(s_tokenOut.balanceOf(s_user), LP_FLOOR, "delivered");
    }

    function test_Fee_NoCandidatePresent_KeeperGoesUnpaid() external {
        Constraints memory c = _eitherConstraints();
        c.rules[0].fees = _fee(0, 2); // only A is a candidate
        _runEither(c, 0, AMOUNT_B);
        assertEq(s_tokenB.balanceOf(s_keeper) + s_tokenIn.balanceOf(s_keeper), 0, "no fee");
        assertEq(s_tokenOut.balanceOf(s_user), LP_FLOOR, "still delivered");
    }

    function test_Fee_CandidateOutsideTheInputs_IsMalformed() external view {
        Constraints memory c = _eitherConstraints();
        c.rules[0].fees[1].asset = 2; // the LP token: not an input
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "status");
    }

    function test_Fee_RuleWithoutInputs_TakesOneCandidate() external view {
        Constraints memory c = _eitherConstraints();
        c.rules[0].inputs = new Input[](0);
        c.rules[0].threshold = 0;
        c.rules[0].fees[1].asset = 2;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "two candidates");
        c.rules[0].fees = _fee(2, 2); // any asset, paid from the holder
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.OK, "one");
    }

    /// A one-shot rule that can run on part of its inputs must drain: otherwise a keeper could take
    /// the profitable input and strand the rest.
    function test_OncePartialThreshold_NeedsDrain() external view {
        Constraints memory c = _pairConstraints();
        c.lifetime.kind = Codes.ONCE;
        c.rules[0].threshold = 1;
        c.rules[0].consume = Codes.EXACT;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.MALFORMED, "exact");
        c.rules[0].consume = Codes.DRAIN;
        assertEq(IntentEvaluator.check(_intent(c, s_user, s_keeper)), IntentEvaluator.OK, "drain");
    }
}

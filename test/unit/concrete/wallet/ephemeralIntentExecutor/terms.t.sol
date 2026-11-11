// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IntentCounter } from "../../../../../src/intent/IntentCounter.sol";
import {
    Codes,
    Constraints,
    Consume,
    Intent,
    Predicate,
    Source,
    Term,
    View
} from "../../../../../src/interfaces/IIntent.sol";
import { IIntentCounter } from "../../../../../src/interfaces/IIntentCounter.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { MockIntentOracle } from "../../../../mocks/MockIntentOracle.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract EphemeralIntentExecutor_Terms_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;

    MockIntentOracle internal s_oracle;
    IntentCounter internal s_counter;

    function setUp() public override {
        super.setUp();
        s_oracle = new MockIntentOracle();
        s_counter = new IntentCounter();
    }

    function _base() internal view returns (Constraints memory) {
        return _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0, Codes.DRAIN);
    }

    function _deliver(Intent memory intent, uint256 amount) internal returns (bytes32 root) {
        root = _root(intent);
        _fund(root, DEPOSIT);
        s_router.clearOuts();
        s_router.addOut(address(s_tokenOut), amount, s_user);
    }

    /// floor = consumedValue(tokenOut) × 99%, priced by an oracle with a one-hour staleness.
    function _valued() internal view returns (Intent memory) {
        Constraints memory c = _base();
        c.sources = new Source[](1);
        c.sources[0] = Source({ kind: Codes.ORACLE, target: address(s_oracle), config: abi.encode(uint32(1 hours)) });
        c.rules[0].inputs[0].price = 0;
        c.terms = new Term[](3);
        c.terms[0] = _term(Codes.OP_DELTA, 1, Codes.OWNER, 0);
        c.terms[1] = _term(Codes.OP_CONSUMED_VALUE, 1, 0, 0);
        c.terms[2] = _term(Codes.OP_MUL_BPS, 1, 0, 9900);
        c.predicates[0] = _pred(Codes.CMP_GTE, 0, 2);
        return _intent(c, s_user, s_keeper);
    }

    function test_ConsumedValue_FloorsAgainstTheOracle() external {
        s_oracle.set(address(s_tokenIn), address(s_tokenOut), 2e18, uint64(block.timestamp));
        Intent memory intent = _valued();
        bytes32 root = _deliver(intent, 198 ether); // 100 × 2 × 99%

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenOut.balanceOf(s_user), 198 ether, "at the floor");
    }

    function test_ConsumedValue_BelowTheFloorReverts() external {
        s_oracle.set(address(s_tokenIn), address(s_tokenOut), 2e18, uint64(block.timestamp));
        Intent memory intent = _valued();
        bytes32 root = _deliver(intent, 197 ether);

        vm.expectRevert(abi.encodeWithSelector(IntentEvaluator.PredicateFailed.selector, uint16(0)));
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
    }

    function test_StaleOracle_Reverts() external {
        // Fixed timestamps: under via-ir, block.timestamp reads in a test can move past a warp.
        vm.warp(1_000_000 + 2 hours);
        s_oracle.set(address(s_tokenIn), address(s_tokenOut), 2e18, 1_000_000);
        Intent memory intent = _valued();
        bytes32 root = _deliver(intent, 198 ether);

        vm.expectRevert(abi.encodeWithSelector(IntentEvaluator.Stale.selector, uint16(0)));
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
    }

    /// floor on a post-state view: tokenOut.balanceOf(owner) >= 200 after execution.
    function test_PostView_Floor() external {
        Constraints memory c = _base();
        c.views = new View[](1);
        c.views[0] = View({
            target: address(s_tokenOut), selector: IERC20.balanceOf.selector, args: abi.encode(s_user), word: 0
        });
        c.terms = new Term[](2);
        c.terms[0] = _term(Codes.OP_POST_VIEW, 0, 0, 0);
        c.terms[1] = _term(Codes.OP_CONST, 0, 0, 200 ether);
        c.predicates[0] = _pred(Codes.CMP_GTE, 0, 1);
        Intent memory intent = _intent(c, s_user, s_keeper);

        bytes32 root = _deliver(intent, 200 ether);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenOut.balanceOf(s_user), 200 ether, "delivered");
    }

    /// A lifetime budget of 150 TIN through the counter: the second 100 TIN execution exceeds it.
    function test_Counter_CapsAcrossExecutions() external {
        Constraints memory c = _base();
        c.sources = new Source[](1);
        c.sources[0] = Source({ kind: Codes.COUNTER, target: address(s_counter), config: "" });
        c.consumes = new Consume[](1);
        c.consumes[0] = Consume({ source: 0, key: "buy", amount: 1, cap: 150 ether, period: 0 });
        Predicate[] memory predicates = new Predicate[](2);
        predicates[0] = c.predicates[0];
        predicates[1] = _pred(Codes.CMP_CONSUMED_WITHIN, 0, 0);
        c.predicates = predicates;
        c.rules[0].then = _two(0, 1);
        Intent memory intent = _intent(c, s_user, s_keeper);

        bytes32 root = _deliver(intent, 200 ether);
        address executor = _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_counter.used(executor, root, "buy", 0), DEPOSIT, "usage recorded under the executor and root");

        vm.roll(block.number + 1);
        _deliver(intent, 200 ether);
        vm.expectRevert(abi.encodeWithSelector(IIntentCounter.CapExceeded.selector, 2 * DEPOSIT, 150 ether));
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
    }

    function test_Counter_OthersCannotWriteYourUsage() external {
        // Any caller writes only its own entries.
        vm.prank(s_stranger);
        s_counter.consume(bytes32("root"), "buy", 100 ether, 1000 ether, 0);
        assertEq(s_counter.used(s_keeper, bytes32("root"), "buy", 0), 0, "untouched");
        assertEq(s_counter.used(s_stranger, bytes32("root"), "buy", 0), 100 ether, "the writer's own");
    }
}

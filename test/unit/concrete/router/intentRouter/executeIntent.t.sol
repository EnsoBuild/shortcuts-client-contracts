// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Constraints, Intent, Lifetime } from "../../../../../src/interfaces/IIntent.sol";
import { Level, Obligation } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { MockGuardian } from "../../../../mocks/MockGuardian.sol";
import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";

contract IntentRouter_ExecuteIntent_Test is IntentRouter_Unit_Concrete_Test {
    function test_Exact_PullsTheSignedAmountAndDelivers() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        bytes memory signature = _sign(intent);
        s_router.addOut(address(s_tokenOut), 200 ether, s_owner);

        _exec(s_keeper, intent, signature);

        assertEq(s_tokenIn.balanceOf(s_keeper), FEE, "fee from the owner to the keeper");
        assertEq(s_tokenIn.balanceOf(address(s_router)), AMOUNT - FEE, "route got the rest");
        assertEq(s_tokenIn.balanceOf(s_owner), 1000 ether - AMOUNT, "exactly the signed amount left the wallet");
        assertEq(s_tokenOut.balanceOf(s_owner), 200 ether, "delivered");
        assertEq(s_tokenIn.balanceOf(address(s_intentRouter)), 0, "router holds nothing");
        assertEq(s_tokenIn.allowance(address(s_intentRouter), address(s_router)), 0, "approval revoked");
    }

    function test_Drain_PullsTheWholeBalance() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        bytes memory signature = _sign(intent);
        // floor = 2 × 1000 consumed
        s_router.addOut(address(s_tokenOut), 2000 ether, s_owner);

        _exec(s_keeper, intent, signature);
        assertEq(s_tokenIn.balanceOf(s_owner), 0, "drained");
        assertEq(s_tokenOut.balanceOf(s_owner), 2000 ether, "delivered");
    }

    function test_Once_SecondExecutionReverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        bytes memory signature = _sign(intent);
        s_router.addOut(address(s_tokenOut), 200 ether, s_owner);
        _exec(s_keeper, intent, signature);

        vm.expectRevert(IntentRouter.Exhausted.selector);
        _exec(s_keeper, intent, signature);
    }

    function test_Scheduled_OncePerWindow() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.lifetime = Lifetime({ kind: Codes.STANDING, interval: 1 days, count: 3 });
        intent.deadline = uint64(intent.start + 30 days);
        bytes memory signature = _sign(intent);
        s_router.addOut(address(s_tokenOut), 200 ether, s_owner);
        _exec(s_keeper, intent, signature);

        vm.expectRevert(IntentRouter.NotYet.selector);
        _exec(s_keeper, intent, signature);

        vm.warp(intent.start + 1 days);
        _exec(s_keeper, intent, signature);
        assertEq(s_tokenOut.balanceOf(s_owner), 400 ether, "two windows, two executions");
    }

    function test_UnscheduledStandingWithInputs_Reverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.lifetime = Lifetime({ kind: Codes.STANDING, interval: 0, count: 0 });
        bytes memory signature = _sign(intent);

        vm.expectRevert(abi.encodeWithSelector(IntentRouter.Rejected.selector, IntentEvaluator.MALFORMED));
        _exec(s_keeper, intent, signature);
    }

    function test_Attestation_Reverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.predicates[0].enforce = Codes.ENFORCE_ATTESTED;
        bytes memory signature = _sign(intent);

        vm.expectRevert(abi.encodeWithSelector(IntentRouter.Rejected.selector, IntentEvaluator.UNSUPPORTED));
        _exec(s_keeper, intent, signature);
    }

    function test_KeeperRouteWithoutOutcome_Reverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.rules[0].then = new uint16[](0);
        bytes memory signature = _sign(intent);

        vm.expectRevert(abi.encodeWithSelector(IntentRouter.Rejected.selector, IntentEvaluator.CUSTODIAL));
        _exec(s_keeper, intent, signature);
    }

    function test_SpendCapOnly_RevertsCustodial() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.terms[2] = _term(Codes.OP_CONST, 0, 0, 0);
        intent.constraints.terms[3] = _term(Codes.OP_SUB, 2, 1, 0);
        bytes memory signature = _sign(intent);

        // Statically bounded, but the floor is negative at execution.
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "passes the static check");
        vm.expectRevert(abi.encodeWithSelector(IntentRouter.Rejected.selector, IntentEvaluator.CUSTODIAL));
        _exec(s_keeper, intent, signature);
    }

    function test_InvalidSignature_Reverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        bytes memory signature = _sign(intent);
        intent.nonce = 8;

        vm.expectRevert(IntentRouter.InvalidSignature.selector);
        _exec(s_keeper, intent, signature);
    }

    function test_Window_And_Chain() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.chainId = 0;
        vm.expectRevert(IntentRouter.WrongChain.selector);
        _exec(s_keeper, intent, "");

        intent = _swapIntent(Codes.EXACT);
        vm.warp(intent.deadline + 1);
        vm.expectRevert(IntentRouter.Expired.selector);
        _exec(s_keeper, intent, "");
    }

    function test_Keeper_ExclusiveUntilHandover() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.exclusive = uint64(intent.start + 1 hours);
        bytes memory signature = _sign(intent);
        s_router.addOut(address(s_tokenOut), 200 ether, s_owner);

        vm.expectRevert(IntentRouter.NotKeeper.selector);
        _exec(s_stranger, intent, signature);

        vm.warp(intent.start + 1 hours);
        _exec(s_stranger, intent, signature);
        assertEq(s_tokenIn.balanceOf(s_stranger), FEE, "anyone after the handover");
    }

    function test_Handoff_PullsExactlyAndForwardsTheFeeValue() external {
        MockGuardian guardian = new MockGuardian(Level.FORWARD);
        Constraints memory c =
            _bridge(address(guardian), uint8(Level.FORWARD), address(s_tokenIn), 10, s_owner, s_owner, AMOUNT, FEE);
        c.rules[0].consume = Codes.EXACT;
        c.lifetime = Lifetime({ kind: Codes.ONCE, interval: 0, count: 0 });
        Intent memory intent = _intent(c, s_owner, s_keeper);
        bytes memory signature = _sign(intent);

        vm.prank(s_keeper);
        s_intentRouter.executeIntent{ value: 0.01 ether }(intent, signature, address(0), new bytes[](0), new bytes[](0));

        assertEq(guardian.lastAmount(), AMOUNT - FEE, "exact, less the fee");
        assertEq(guardian.lastValue(), 0.01 ether, "messaging fee forwarded");
        Obligation memory o = guardian.lastObligation();
        assertEq(o.minAmount, AMOUNT - FEE, "minimum");
        assertEq(o.chainId, 10, "destination");
        assertEq(address(s_intentRouter).balance, 0, "router holds no native");
    }
}

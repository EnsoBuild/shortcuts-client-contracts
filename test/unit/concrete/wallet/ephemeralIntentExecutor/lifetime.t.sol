// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Codes, Constraints, Intent, Lifetime } from "../../../../../src/interfaces/IIntent.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

/// Execution records live in the factory, keyed by the executor's own address.
contract EphemeralIntentExecutor_Lifetime_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;

    function _swapIntent(Lifetime memory lifetime) internal view returns (Intent memory intent) {
        Constraints memory c =
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0, Codes.DRAIN);
        c.lifetime = lifetime;
        intent = _intent(c, s_user, s_keeper);
        intent.deadline = uint64(block.timestamp + 30 days);
    }

    function _deposit(bytes32 root, Intent memory intent) internal returns (Execution memory e) {
        _fund(root, DEPOSIT);
        s_router.clearOuts();
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);
        e = _withRoute(_execution(intent), hex"c0ffee");
    }

    function test_Once_ExecutesOnceThenRefundsAReDeposit() external {
        Intent memory intent = _swapIntent(Lifetime({ kind: Codes.ONCE, interval: 0, count: 0 }));
        bytes32 root = _root(intent);
        _run(s_keeper, root, _deposit(root, intent));
        assertEq(s_tokenOut.balanceOf(s_user), 200 ether, "first execution");

        vm.roll(block.number + 1);
        _run(s_keeper, root, _deposit(root, intent));
        assertEq(s_tokenOut.balanceOf(s_user), 200 ether, "no second execution");
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "the re-deposit is returned");
    }

    function test_Scheduled_WaitsForTheNextWindow() external {
        Intent memory intent = _swapIntent(Lifetime({ kind: Codes.STANDING, interval: 1 days, count: 0 }));
        bytes32 root = _root(intent);
        _run(s_keeper, root, _deposit(root, intent));

        // Absolute warps: under via-ir a test's block.timestamp reads can be cached.
        uint256 start = intent.start;
        vm.roll(block.number + 1);
        vm.warp(start + 12 hours);
        Execution memory e = _deposit(root, intent);
        vm.expectRevert(IntentEvaluator.NotYet.selector);
        _run(s_keeper, root, e);

        vm.warp(start + 1 days); // window 2, anchored at start
        _run(s_keeper, root, e);
        assertEq(s_tokenOut.balanceOf(s_user), 400 ether, "one execution per window");
    }

    function test_Counted_StopsAtTheLimit() external {
        Intent memory intent = _swapIntent(Lifetime({ kind: Codes.STANDING, interval: 0, count: 2 }));
        bytes32 root = _root(intent);
        _run(s_keeper, root, _deposit(root, intent));
        vm.roll(block.number + 1);
        _run(s_keeper, root, _deposit(root, intent));
        vm.roll(block.number + 1);
        _run(s_keeper, root, _deposit(root, intent));

        assertEq(s_tokenOut.balanceOf(s_user), 400 ether, "two executions");
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "the third deposit is returned");
    }

    function test_UnscheduledStanding_KeepsNoRecord() external {
        Intent memory intent = _swapIntent(Lifetime({ kind: Codes.STANDING, interval: 0, count: 0 }));
        bytes32 root = _root(intent);
        _run(s_keeper, root, _deposit(root, intent));
        assertEq(s_factory.records(s_factory.getAddress(root)), 0, "deposit addresses need no record");
    }
}

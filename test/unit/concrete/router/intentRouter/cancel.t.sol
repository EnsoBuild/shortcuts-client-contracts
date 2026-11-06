// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Intent, Lifetime } from "../../../../../src/interfaces/IIntent.sol";
import { IIntentRouter } from "../../../../../src/interfaces/IIntentRouter.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";

contract IntentRouter_Cancel_Test is IntentRouter_Unit_Concrete_Test {
    function test_CancelledBeforeFirstUse_Reverts() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        bytes memory signature = _sign(intent);
        uint256[] memory nonces = new uint256[](1);
        nonces[0] = intent.nonce;

        vm.expectEmit(address(s_intentRouter));
        emit IIntentRouter.IntentCancelled(s_owner, intent.nonce);
        vm.prank(s_owner);
        s_intentRouter.cancel(nonces);

        vm.expectRevert(IntentRouter.Exhausted.selector);
        _exec(s_keeper, intent, signature);
    }

    /// The terminal record is checked before anything a lifetime reads, so it also stops a
    /// standing intent with a schedule.
    function test_CancelStopsAStandingIntent() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        intent.constraints.lifetime = Lifetime({ kind: Codes.STANDING, interval: 1 days, count: 0 });
        intent.deadline = uint64(intent.start + 30 days);
        bytes memory signature = _sign(intent);
        s_router.addOut(address(s_tokenOut), 200 ether, s_owner);
        _exec(s_keeper, intent, signature);

        uint256[] memory nonces = new uint256[](1);
        nonces[0] = intent.nonce;
        vm.prank(s_owner);
        s_intentRouter.cancel(nonces);

        vm.warp(intent.start + 1 days);
        vm.expectRevert(IntentRouter.Exhausted.selector);
        _exec(s_keeper, intent, signature);
    }

    function test_CancelsABatch() external {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 1;
        nonces[1] = 2;
        nonces[2] = 3;
        vm.prank(s_owner);
        s_intentRouter.cancel(nonces);
        for (uint256 i; i < 3; ++i) {
            assertEq(s_intentRouter.records(s_owner, nonces[i]), type(uint64).max, "terminal");
        }
        assertEq(s_intentRouter.records(s_stranger, 1), 0, "only the caller's own nonces");
    }
}

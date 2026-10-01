// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Intent } from "../../../../../src/interfaces/IIntent.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";

contract IntentRouter_Cancel_Unit_Concrete_Test is IntentRouter_Unit_Concrete_Test {
    function test_WhenTheOwnerCancelsANonce() external {
        // it should emit IntentCancelled
        vm.expectEmit(address(s_router));
        emit IntentRouter.IntentCancelled(s_owner, 5);

        vm.prank(s_owner);
        s_router.cancel(5);

        // it should mark the nonce used
        assertEq(s_router.nonceBitmap(s_owner, 0), 1 << 5);
        Intent memory intent = _intent();
        intent.nonce = 5;
        bytes memory signature = _sign(intent);
        bytes memory route = _transferRoute(address(s_tokenOut), s_recipient, 50 ether);
        vm.expectRevert(IntentRouter.NonceUsed.selector);
        _execute(intent, signature, route);

        // it should leave other nonces and owners untouched
        assertEq(s_router.nonceBitmap(s_owner, 1), 0);
        assertEq(s_router.nonceBitmap(s_keeper, 0), 0);
        intent.nonce = 6;
        _execute(intent, route);
        assertEq(s_router.nonceBitmap(s_owner, 0), (1 << 5) | (1 << 6));
    }

    function test_WhenTheNonceIsAlreadyUsed() external {
        Intent memory intent = _intent();
        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));

        // it should revert with NonceUsed
        vm.prank(s_owner);
        vm.expectRevert(IntentRouter.NonceUsed.selector);
        s_router.cancel(intent.nonce);
    }
}

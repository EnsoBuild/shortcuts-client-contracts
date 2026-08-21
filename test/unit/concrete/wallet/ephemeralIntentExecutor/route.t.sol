// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralIntentExecutor, Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockIntentRouter } from "../../../../mocks/MockIntentRouter.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Route_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    function test_WhenTriggersAreUnmet() external {
        Intent memory intent = _intent();
        _fund(intent, 50 ether); // below the 100 ether trigger

        // it should revert with Underfunded
        vm.expectRevert(EphemeralIntentExecutor.Underfunded.selector);
        _execute(intent, "");
    }

    function test_WhenExecutedBeforeStart() external {
        Intent memory intent = _intent();
        intent.start = uint64(block.timestamp + 1 hours);
        _fund(intent, 100 ether);

        // it should revert with TooEarly
        vm.expectRevert(EphemeralIntentExecutor.TooEarly.selector);
        _execute(intent, "");
    }

    function test_WhenThePayloadRuns() external {
        Intent memory intent = _intent();
        intent.keeperFee = _erc20(address(s_tokenIn), 5 ether);
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 1 ether);
        s_router.setPull(address(s_tokenIn), 90 ether);

        _execute(intent, "");

        // it should call the router with the committed payload
        assertEq(s_router.lastData(), hex"deadbeef");
        assertEq(s_router.lastCaller(), predicted);
        assertEq(s_router.lastValue(), 0);

        // it should approve trigger tokens to the router for the call (fee off the top)
        assertEq(s_router.lastAllowance(), 95 ether);

        // it should revoke approvals after the call
        assertEq(s_tokenIn.allowance(predicted, address(s_router)), 0);

        // it should pay the keeper fee
        assertEq(s_tokenIn.balanceOf(s_keeper), 5 ether);

        // it should sweep remaining native to the refund recipient
        assertEq(s_user.balance, 1 ether);
    }

    function test_WhenANativeTriggerExists() external {
        Intent memory intent = _intent();
        intent.triggers[0] = _native(1 ether);
        address predicted = s_factory.getAddress(intent);
        vm.deal(predicted, 1 ether);

        _execute(intent, "");

        // it should forward the native balance as call value
        assertEq(s_router.lastValue(), 1 ether);
        assertEq(address(s_router).balance, 1 ether);
    }

    function test_WhenTheFeeIsNative() external {
        Intent memory intent = _intent();
        intent.keeperFee = _native(1 ether);
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 3 ether);
        uint256 keeperBefore = s_keeper.balance;

        _execute(intent, "");

        // it should pay the keeper in native
        assertEq(s_keeper.balance, keeperBefore + 1 ether);
        assertEq(s_user.balance, 2 ether); // remainder rides the selfdestruct
    }

    function test_WhenTheRouterCallReverts() external {
        Intent memory intent = _intent();
        _fund(intent, 100 ether);
        s_router.setRevert(true);

        // it should bubble the revert reason
        vm.expectRevert(MockIntentRouter.MockRouterRevert.selector);
        _execute(intent, "");
    }

    function test_WhenTheFeeCannotBePaid() external {
        Intent memory intent = _intent();
        intent.keeperFee = _erc20(address(s_tokenIn), 1000 ether); // more than delivered
        _fund(intent, 100 ether);

        // it should revert with SendFailed
        vm.expectRevert(EphemeralIntentExecutor.SendFailed.selector);
        _execute(intent, "");
    }
}

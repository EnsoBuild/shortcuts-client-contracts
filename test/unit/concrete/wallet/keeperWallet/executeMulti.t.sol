// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Call, KeeperWallet, Result } from "../../../../../src/wallet/KeeperWallet.sol";
import { KeeperWallet_Unit_Concrete_Test, Target } from "./KeeperWallet.t.sol";

contract KeeperWallet_ExecuteMulti_Unit_Concrete_Test is KeeperWallet_Unit_Concrete_Test {
    function test_WhenAllCallsSucceed() external {
        // it should execute every call and return each response
        Call[] memory calls = new Call[](2);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.func, ()) });
        calls[1] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.increment, ()) });

        vm.prank(s_executor);
        Result[] memory results = s_wallet.executeMulti(calls);

        assertEq(results.length, 2);
        assertTrue(results[0].success);
        assertEq(abi.decode(results[0].returnData, (uint256)), 42);
        assertTrue(results[1].success);
        assertEq(s_target.counter(), 1);
    }

    function test_WhenCallerIsOwner() external {
        // it should execute the calls
        Call[] memory calls = new Call[](1);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.increment, ()) });

        vm.prank(s_owner);
        s_wallet.executeMulti(calls);

        assertEq(s_target.counter(), 1);
    }

    function test_WhenOptionalCallFails() external {
        // it should record the failure and continue with the remaining calls
        Call[] memory calls = new Call[](3);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.increment, ()) });
        calls[1] =
            Call({ target: address(s_target), required: false, data: abi.encodeCall(Target.revertCustomError, ()) });
        calls[2] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.increment, ()) });

        vm.prank(s_executor);
        Result[] memory results = s_wallet.executeMulti(calls);

        assertTrue(results[0].success);
        assertFalse(results[1].success);
        assertEq(results[1].returnData, abi.encodeWithSelector(Target.Target_Revert.selector));
        assertTrue(results[2].success);
        assertEq(s_target.counter(), 2);
    }

    function test_WhenCallsEmpty() external {
        // it should return an empty results array
        vm.prank(s_executor);
        Result[] memory results = s_wallet.executeMulti(new Call[](0));

        assertEq(results.length, 0);
    }

    function test_RevertWhen_RequiredCallRevertsString() external {
        // it should bubble up the revert reason
        Call[] memory calls = new Call[](1);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.revertString, ()) });

        vm.prank(s_executor);
        vm.expectRevert(bytes("Test revert"));
        s_wallet.executeMulti(calls);
    }

    function test_RevertWhen_RequiredCallRevertsCustomError() external {
        // it should bubble up the custom error
        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.revertCustomError, ()) });

        vm.prank(s_executor);
        vm.expectRevert(Target.Target_Revert.selector);
        s_wallet.executeMulti(calls);
    }

    function test_RevertWhen_RequiredCallRevertsNoReason() external {
        // it should revert with ExecutionFailedNoReason
        Call[] memory calls = new Call[](1);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.revertNoReason, ()) });

        vm.prank(s_executor);
        vm.expectRevert(KeeperWallet.KeeperWallet_ExecutionFailedNoReason.selector);
        s_wallet.executeMulti(calls);
    }

    function test_RevertWhen_RequiredCallFailsAfterSuccessfulCalls() external {
        // it should revert the entire batch including earlier successful calls
        Call[] memory calls = new Call[](2);
        calls[0] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.increment, ()) });
        calls[1] = Call({ target: address(s_target), required: true, data: abi.encodeCall(Target.revertString, ()) });

        vm.prank(s_executor);
        vm.expectRevert(bytes("Test revert"));
        s_wallet.executeMulti(calls);

        assertEq(s_target.counter(), 0);
    }

    function test_RevertWhen_CallerNotAuthorized() external {
        // it should revert when caller is neither owner nor executor
        vm.prank(s_user);
        vm.expectRevert(abi.encodeWithSelector(KeeperWallet.KeeperWallet_InvalidSender.selector, s_user));
        s_wallet.executeMulti(new Call[](0));
    }
}

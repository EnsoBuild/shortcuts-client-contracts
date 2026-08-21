// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Constrained, EphemeralIntentExecutor, Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Constrained_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    function test_WhenTheDeltaClearsTheMinimum() external {
        Intent memory intent = _constrainedIntent(50 ether, address(0), 0);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 60 ether);

        _execute(intent, hex"beefcafe");

        // it should call the router with the keeper route
        assertEq(s_router.lastData(), hex"beefcafe");

        // it should forward the delta to the recipient
        assertEq(s_tokenOut.balanceOf(s_recipient), 60 ether);
    }

    function test_WhenTokenOutIsNative() external {
        Intent memory intent = _constrainedIntent(1 ether, address(0), 0);
        Constrained memory c = abi.decode(intent.payload, (Constrained));
        c.tokenOut = address(0);
        intent.payload = abi.encode(c);
        _fund(intent, 100 ether);
        vm.deal(address(s_router), 2 ether);
        s_router.setOutNative(2 ether);

        _execute(intent, hex"beefcafe");

        // it should forward the native delta to the recipient
        assertEq(s_recipient.balance, 2 ether);
    }

    function test_WhenTheDeltaIsBelowTheMinimum() external {
        Intent memory intent = _constrainedIntent(50 ether, address(0), 0);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 40 ether);

        // it should revert with Insufficient
        vm.expectRevert(EphemeralIntentExecutor.Insufficient.selector);
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheExclusivityWindowIsOpen() external {
        Intent memory intent = _constrainedIntent(0, s_keeper, uint64(block.timestamp + 1 hours));
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether);

        // it should revert with Exclusive for other keepers
        address other = vm.addr(9);
        vm.prank(other);
        vm.expectRevert(EphemeralIntentExecutor.Exclusive.selector);
        s_factory.executeIntent(intent, hex"beefcafe", new address[](0));

        // it should execute for the exclusive keeper
        _execute(intent, hex"beefcafe");
        assertEq(s_tokenOut.balanceOf(s_recipient), 1 ether);
    }

    function test_WhenTheExclusivityWindowHasPassed() external {
        Intent memory intent = _constrainedIntent(0, s_keeper, uint64(block.timestamp));
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether);
        vm.warp(block.timestamp + 1);

        // it should execute for any keeper
        address other = vm.addr(9);
        vm.prank(other);
        s_factory.executeIntent(intent, hex"beefcafe", new address[](0));
        assertEq(s_tokenOut.balanceOf(s_recipient), 1 ether);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { EphemeralIntentExecutor, Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockIntentRouter } from "../../../../mocks/MockIntentRouter.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";
import { Vm } from "forge-std/Vm.sol";

/// The owner arms: when the factory's caller is `intent.owner`, bytes mean "run them"
/// and no bytes mean "take everything back". Neither arm consults the chain, window,
/// trigger, exclusivity, or outcome gates — those protect the user from the keeper,
/// and here the user is the caller.
contract EphemeralIntentExecutor_Owner_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    bytes32 private constant TRANSFER = keccak256("Transfer(address,address,uint256)");

    function _executeAsOwner(Intent memory intent, bytes memory route, Token[] memory sweep) private returns (address) {
        vm.prank(s_user);
        return s_factory.executeIntent(intent, route, sweep);
    }

    /// Transfer events emitted by `token` with `from` as the sender.
    function _transfersFrom(Vm.Log[] memory logs, address token, address from) private pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == token && logs[i].topics.length == 3 && logs[i].topics[0] == TRANSFER
                    && address(uint160(uint256(logs[i].topics[1]))) == from
            ) {
                ++n;
            }
        }
    }

    function test_WhenTheOwnerCallsWithoutARoute() external {
        MockERC20 feeToken = new MockERC20("Fee", "FEE");
        Intent memory intent = _intent();
        intent.keeperFee = _fee(address(feeToken), 5 ether, 5 ether);
        address predicted = _fund(intent, 100 ether);
        feeToken.mint(predicted, 42 ether);
        vm.deal(predicted, 1 ether);

        vm.recordLogs();
        _executeAsOwner(intent, "", new Token[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // it should refund the trigger tokens before the deadline
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);

        // it should pay no fee — the fee token leaves in one sweep, not fee plus remainder
        assertEq(feeToken.balanceOf(s_user), 42 ether);
        assertEq(_transfersFrom(logs, address(feeToken), predicted), 1);

        // it should not call the router
        assertEq(s_router.lastCaller(), address(0));

        // it should sweep native via selfdestruct
        assertEq(s_user.balance, 1 ether);
        assertEq(predicted.code.length, 0);
    }

    function test_WhenTheOwnerCallsBeforeStart() external {
        Intent memory intent = _intent();
        intent.start = uint64(block.timestamp + 1 hours);
        _fund(intent, 100 ether);

        // the keeper is gated
        vm.expectRevert(EphemeralIntentExecutor.TooEarly.selector);
        _execute(intent, "");

        // it should refund without waiting for the start gate
        _executeAsOwner(intent, "", new Token[](0));
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    /// forge-config: default.isolate = true
    function test_WhenTheOwnerCallsInsideTheExclusivityWindow() external {
        Intent memory intent = _constrainedIntent(1 ether, s_keeper, uint64(block.timestamp + 1 hours));
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether, s_recipient);

        // it should refund without reverting Exclusive
        _executeAsOwner(intent, "", new Token[](0));
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);

        // it should leave the exclusive keeper nothing to execute
        vm.expectRevert(EphemeralIntentExecutor.Underfunded.selector);
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheOwnerListsExtraTokens() external {
        Intent memory intent = _intent();
        address predicted = _fund(intent, 100 ether);
        MockERC20 extra = new MockERC20("Extra", "EXT");
        extra.mint(predicted, 42 ether);

        Token[] memory sweep = new Token[](2);
        sweep[0] = _erc20(address(extra), 0);
        sweep[1] = _erc20(address(s_tokenIn), 0); // a trigger, listed again

        vm.recordLogs();
        _executeAsOwner(intent, "", sweep);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // it should sweep them alongside the triggers
        assertEq(extra.balanceOf(s_user), 42 ether);
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);

        // it should tolerate a listed trigger token — the second pass reads a zero
        // balance and skips, so the trigger moves exactly once
        assertEq(_transfersFrom(logs, address(s_tokenIn), predicted), 1);
    }

    /// forge-config: default.isolate = true
    function test_WhenTheOwnerSubmitsARoute() external {
        Intent memory intent = _intent();
        intent.keeperFee = _fee(address(s_tokenIn), 5 ether, 1 ether);
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 1 ether);
        s_router.setPull(address(s_tokenIn), 90 ether);

        _executeAsOwner(intent, hex"c0ffee", new Token[](0));

        // it should call the router with the owner's bytes, not the committed payload
        assertEq(s_router.lastData(), hex"c0ffee");
        assertEq(s_router.lastCaller(), predicted);

        // it should pass the trigger tokens with live balances
        (, bytes memory liveData) = s_router.lastTokensIn(0);
        (, uint256 liveAmount) = abi.decode(liveData, (address, uint256));
        assertEq(liveAmount, 100 ether);

        // it should not take a fee off the top
        assertEq(s_router.lastAllowance(), 100 ether);
        assertEq(s_tokenIn.balanceOf(s_user), 0);

        // it should revoke approvals after the call
        assertEq(s_tokenIn.allowance(predicted, address(s_router)), 0);

        // it should sweep remaining native to the owner
        assertEq(s_user.balance, 1 ether);

        // it should leave route residue recoverable by an owner refund
        assertEq(s_tokenIn.balanceOf(predicted), 10 ether);
        _executeAsOwner(intent, "", new Token[](0));
        assertEq(s_tokenIn.balanceOf(s_user), 10 ether);
    }

    function test_WhenTheOwnerSubmitsARouteUnderClosedGates() external {
        // Every gate shut at once: before start, underfunded triggers, another keeper's
        // exclusivity window, and a route that delivers nothing to the recipient.
        Intent memory intent = _constrainedIntent(50 ether, s_keeper, uint64(block.timestamp + 1 hours));
        intent.start = uint64(block.timestamp + 1 hours);
        _fund(intent, 50 ether);

        vm.expectRevert(EphemeralIntentExecutor.TooEarly.selector);
        _execute(intent, hex"c0ffee");

        // it should execute without the start, trigger, exclusivity, or outcome gates
        _executeAsOwner(intent, hex"c0ffee", new Token[](0));
        assertEq(s_router.lastData(), hex"c0ffee");
        (, bytes memory liveData) = s_router.lastTokensIn(0);
        (, uint256 liveAmount) = abi.decode(liveData, (address, uint256));
        assertEq(liveAmount, 50 ether);
    }

    function test_WhenTheOwnerSubmitsARouteOutsideTheWindow() external {
        Intent memory intent = _intent();
        intent.chainId = 999;
        address predicted = _fund(intent, 100 ether);
        vm.warp(intent.deadline + 1);

        _executeAsOwner(intent, hex"c0ffee", new Token[](0));

        // it should route rather than refund
        assertEq(s_router.lastData(), hex"c0ffee");
        assertEq(s_router.lastCaller(), predicted);
        assertEq(s_tokenIn.balanceOf(s_user), 0);
    }

    function test_WhenTheOwnerRouteReverts() external {
        Intent memory intent = _intent();
        _fund(intent, 100 ether);
        s_router.setRevert(true);

        // it should bubble the revert reason
        vm.expectRevert(MockIntentRouter.MockRouterRevert.selector);
        _executeAsOwner(intent, hex"c0ffee", new Token[](0));

        // it should leave the refund arm available
        _executeAsOwner(intent, "", new Token[](0));
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    function test_WhenAThirdPartySubmitsARouteInROUTEMode() external {
        Intent memory intent = _intent();
        _fund(intent, 100 ether);

        _execute(intent, hex"c0ffee");

        // it should ignore the bytes and run the committed payload
        assertEq(s_router.lastData(), hex"deadbeef");
    }

    function test_WhenTheOwnerIsZeroAndAKeeperSubmitsARoute() external {
        Intent memory intent = _intent();
        intent.owner = address(0);
        _fund(intent, 100 ether);

        _execute(intent, hex"c0ffee");

        // it should not grant the keeper owner privileges — the standard path runs
        assertEq(s_router.lastData(), hex"deadbeef");
    }
}

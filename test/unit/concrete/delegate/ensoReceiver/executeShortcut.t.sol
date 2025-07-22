// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../../../../../src/AbstractEnsoShortcuts.sol";
import { EIP7702EnsoShortcuts } from "../../../../../src/delegate/EIP7702EnsoShortcuts.sol";
import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";

import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS } from "account-abstraction-v7/core/Helpers.sol";
import { PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoReceiver_ExecuteShortcut_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test {
    function test_RevertWhen_Reentrant() external {
        vm.skip(true, "Requires executeShortcut to call executeShortcut");
        // it should revert
    }

    modifier whenNonReentrant() {
        _;
    }

    function test_RevertWhen_CallerIsNotEnsoReceiverOrOwner() external whenNonReentrant {
        vm.skip(true);
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.executeShortcut(accountId, requestId, commands, state);
    }

    modifier whenCallerIsEnsoReceiver() {
        vm.startPrank(address(s_ensoReceiver));
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ShortcutExecutionFailed1() external whenNonReentrant whenCallerIsEnsoReceiver {
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        // it should revert
        vm.expectRevert(bytes("Invalid calltype"));
        s_ensoReceiver.executeShortcut(accountId, requestId, commands, state);
    }

    function test_WhenShortcutExecutionIsSuccessful1() external whenNonReentrant whenCallerIsEnsoReceiver {
        vm.skip(true, "[Revert] Only one return value permitted (static)");

        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1(s_owner);
        shortcut.from = address(s_ensoReceiver);
        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(bytes32(0), keccak256(bytes("0123456789ABCDEF")));
        (bool success, bytes memory response) = address(s_ensoReceiver).call(shortcut.txData);

        // it should apply shortcut state changes
        assertTrue(success);
        assertTrue(response.length > 0);
        // TODO: assert shortcut state changes
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ShortcutExecutionFailed2() external whenNonReentrant whenCallerIsOwner {
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        // it should revert
        vm.expectRevert(bytes("Invalid calltype"));
        s_ensoReceiver.executeShortcut(accountId, requestId, commands, state);
    }

    function test_WhenShortcutExecutionIsSuccessful2() external whenNonReentrant whenCallerIsOwner {
        vm.skip(true, "[Revert] Only one return value permitted (static)");

        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1(s_owner);
        shortcut.from = address(s_ensoReceiver);
        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(bytes32(0), keccak256(bytes("0123456789ABCDEF")));
        (bool success, bytes memory response) = address(s_ensoReceiver).call(shortcut.txData);

        // it should apply shortcut state changes
        assertTrue(success);
        assertTrue(response.length > 0);
        // TODO: assert shortcut state changes
    }
}

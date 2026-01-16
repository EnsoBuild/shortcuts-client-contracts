// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../../../../../src/AbstractEnsoShortcuts.sol";
import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { ExecuteShortcutParams, ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { VM as WeirollVM } from "enso-weiroll-1.4.1/VM.sol";
import { console2 } from "forge-std/Test.sol";

contract EnsoReceiver_ExecuteShortcut_SenderIsEnsoReceiver_Unit_Concrete_Test is
    EnsoReceiver_Unit_Concrete_Test,
    TokenBalanceHelper
{
    struct Balances {
        uint256 receiverTokenIn;
        uint256 receiverTokenOut;
        uint256 feeReceiverTokenIn;
        uint256 feeReceiverTokenOut;
        uint256 ensoReceiverTokenIn;
        uint256 ensoReceiverTokenOut;
    }

    function test_RevertWhen_Reentrant() external {
        // Get shortcut
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut3(address(s_ensoReceiver));
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        // it should revert
        vm.startPrank(address(s_ensoReceiver));
        vm.expectRevert(
            abi.encodeWithSelector(WeirollVM.ExecutionFailed.selector, 0, address(s_ensoReceiver), "Unknown")
        );
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );
    }

    modifier whenNonReentrant() {
        _;
    }

    function test_RevertWhen_CallerIsNotEnsoReceiverNorOwner() external whenNonReentrant {
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

    function test_RevertWhen_ShortcutExecutionFailed() external whenNonReentrant whenCallerIsEnsoReceiver {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0] - 1); // NOTE: force shortcut failure

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                WeirollVM.ExecutionFailed.selector, 1, 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7, "Unknown"
            )
        );
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );
    }

    function test_WhenShortcutExecutionSucceeded() external whenNonReentrant whenCallerIsEnsoReceiver {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(executeShortcutParams.accountId, executeShortcutParams.requestId);
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should apply shortcut state changes
        assertBalanceDiff(pre.receiverTokenIn, post.receiverTokenIn, 0, "Receiver TokenIn (ETH)");
        assertBalanceDiff(
            pre.receiverTokenOut,
            post.receiverTokenOut,
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver TokenOut (WETH)"
        );
        assertBalanceDiff(
            pre.feeReceiverTokenIn, post.feeReceiverTokenIn, int256(shortcut.fee), "FeeReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)");
    }
}

contract EnsoReceiver_ExecuteShortcut_SenderIsOwner_Unit_Concrete_Test is
    EnsoReceiver_Unit_Concrete_Test,
    TokenBalanceHelper
{
    struct Balances {
        uint256 receiverTokenIn;
        uint256 receiverTokenOut;
        uint256 feeReceiverTokenIn;
        uint256 feeReceiverTokenOut;
        uint256 ensoReceiverTokenIn;
        uint256 ensoReceiverTokenOut;
    }

    function test_RevertWhen_Reentrant() external {
        // Get shortcut
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut3(address(s_ensoReceiver));
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        // it should revert
        vm.startPrank(address(s_owner));
        vm.expectRevert(
            abi.encodeWithSelector(WeirollVM.ExecutionFailed.selector, 0, address(s_ensoReceiver), "Unknown")
        );
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );
    }

    modifier whenNonReentrant() {
        _;
    }

    function test_RevertWhen_CallerIsNotEnsoReceiverNorOwner() external whenNonReentrant {
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.executeShortcut(accountId, requestId, commands, state);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(s_owner));
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ShortcutExecutionFailed() external whenNonReentrant whenCallerIsOwner {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0] - 1); // NOTE: force shortcut failure

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                WeirollVM.ExecutionFailed.selector, 1, 0xDe09E74d4888Bc4e65F589e8c13Bce9F71DdF4c7, "Unknown"
            )
        );
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );
    }

    function test_WhenShortcutExecutionSucceeded() external whenNonReentrant whenCallerIsOwner {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);
        ExecuteShortcutParams memory executeShortcutParams = ShortcutsEthereum.decodeShortcutTxData(shortcut.txData);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(executeShortcutParams.accountId, executeShortcutParams.requestId);
        s_ensoReceiver.executeShortcut(
            executeShortcutParams.accountId,
            executeShortcutParams.requestId,
            executeShortcutParams.commands,
            executeShortcutParams.state
        );

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should apply shortcut state changes
        assertBalanceDiff(pre.receiverTokenIn, post.receiverTokenIn, 0, "Receiver TokenIn (ETH)");
        assertBalanceDiff(
            pre.receiverTokenOut,
            post.receiverTokenOut,
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver TokenOut (WETH)"
        );
        assertBalanceDiff(
            pre.feeReceiverTokenIn, post.feeReceiverTokenIn, int256(shortcut.fee), "FeeReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)");
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../../../../../src/AbstractEnsoShortcuts.sol";
import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { Withdrawable } from "../../../../../src/utils/Withdrawable.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";

import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { ExecuteShortcutParams, ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";

import { ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { Vm, console2 } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoReceiver_SafeExecute_SenderIsEntryPoint_Unit_Concrete_Test is
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

    function test_RevertWhen_CallerIsNotEntryPointNorOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.safeExecute(IERC20(address(0)), uint256(777), "");
    }

    modifier whenCallerIsEntryPoint() {
        vm.deal(address(s_entryPoint), 1000 ether);
        vm.startPrank(address(s_entryPoint));
        _;
        vm.stopPrank();
    }

    function test_WhenShortcutExecutionSucceeded() external whenCallerIsEntryPoint {
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

        // NOTE: it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(executeShortcutParams.accountId, executeShortcutParams.requestId);
        // it should emit ShortcutExecutionSuccessful
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionSuccessful();
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it apply shortcut state changes
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

    modifier whenShortcutExecutionFailed() {
        _;
    }

    modifier whenTokenInIsNativeToken() {
        _;
    }

    function test_WhenWithdrawCallIsUnsuccessful()
        external
        whenCallerIsEntryPoint
        whenShortcutExecutionFailed
        whenTokenInIsNativeToken
    {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0] - 1); // NOTE: force withdraw failure

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Withdrawable.WithdrawFailed.selector));
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);
    }

    function test_WhenWithdrawCallIsSuccessful()
        external
        whenCallerIsEntryPoint
        whenShortcutExecutionFailed
        whenTokenInIsNativeToken
    {
        // Get shortcut
        // NOTE: force shortcut failure by replacing `EnsoShortcutsHelpers` address with Zero address
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1(address(s_weth), address(0), s_owner);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecutionFailed
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionFailed(hex"08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000284f6e6c79206f6e652072657475726e2076616c7565207065726d6974746564202873746174696329000000000000000000000000000000000000000000000000");
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should send native token amount to owner
        assertBalanceDiff(
            pre.receiverTokenIn, post.receiverTokenIn, int256(shortcut.amountsIn[0]), "Receiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.receiverTokenOut, post.receiverTokenOut, 0, "Receiver TokenOut (WETH)");
        assertBalanceDiff(pre.feeReceiverTokenIn, post.feeReceiverTokenIn, 0, "FeeReceiver TokenIn (ETH)");
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)");
    }

    modifier whenTokenInIsNotNativeToken() {
        _;
    }

    function test_WhenWithdrawSafeTransferIsUnsuccessful()
        external
        whenCallerIsEntryPoint
        whenShortcutExecutionFailed
        whenTokenInIsNotNativeToken
    {
        // Get shortcut
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut2(
            address(s_weth), address(s_ensoShortcutsHelpers), s_owner, 0x6AA68C46eD86161eB318b1396F7b79E386e88676
        );

        // Top-up EnsoReceiver with WETH (as EntryPoint)
        s_weth.deposit{ value: shortcut.amountsIn[0] }(); // NOTE: as EntryPoint
        s_weth.transfer(address(s_ensoReceiver), shortcut.amountsIn[0] - 1);

        // it should revert
        vm.expectRevert(bytes(""), address(s_weth));
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);
    }

    function test_WhenWithdrawSafeTransferIsSuccessful()
        external
        whenCallerIsEntryPoint
        whenShortcutExecutionFailed
        whenTokenInIsNotNativeToken
    {
        // Get shortcut
        // NOTE: force shortcut failure by replacing `EnsoShortcutsHelpers` address with Zero address
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut2(
            address(s_weth), address(0), s_owner, 0x6AA68C46eD86161eB318b1396F7b79E386e88676
        );

        // Top-up EnsoReceiver with WETH (as EntryPoint)
        s_weth.deposit{ value: shortcut.amountsIn[0] }(); // NOTE: as EntryPoint
        s_weth.transfer(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecutionFailed
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionFailed(hex"08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000284f6e6c79206f6e652072657475726e2076616c7565207065726d6974746564202873746174696329000000000000000000000000000000000000000000000000");
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should transfer token amount to owner
        assertBalanceDiff(
            pre.receiverTokenIn, post.receiverTokenIn, int256(shortcut.amountsIn[0]), "Receiver TokenIn (WETH)"
        );
        assertBalanceDiff(pre.receiverTokenOut, post.receiverTokenOut, 0, "Receiver TokenOut (ETH)");
        assertBalanceDiff(pre.feeReceiverTokenIn, post.feeReceiverTokenIn, 0, "FeeReceiver TokenIn (WETH)");
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (ETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (WETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (ETH)");
    }
}

contract EnsoReceiver_SafeExecute_SenderIsOwner_Unit_Concrete_Test is
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

    function test_RevertWhen_CallerIsNotEntryPointNorOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.safeExecute(IERC20(address(0)), uint256(777), "");
    }

    modifier whenCallerIsOwner() {
        vm.deal(address(s_owner), 1000 ether);
        vm.startPrank(address(s_owner));
        _;
        vm.stopPrank();
    }

    function test_WhenShortcutExecutionSucceeded() external whenCallerIsOwner {
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

        // NOTE: it should emit ShortcutExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractEnsoShortcuts.ShortcutExecuted(executeShortcutParams.accountId, executeShortcutParams.requestId);
        // it should emit ShortcutExecutionSuccessful
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionSuccessful();
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it apply shortcut state changes
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

    modifier whenShortcutExecutionFailed() {
        _;
    }

    modifier whenTokenInIsNativeToken() {
        _;
    }

    function test_WhenWithdrawCallIsUnsuccessful()
        external
        whenCallerIsOwner
        whenShortcutExecutionFailed
        whenTokenInIsNativeToken
    {
        // Get shortcut
        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut1(address(s_weth), address(s_ensoShortcutsHelpers), s_owner);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0] - 1); // NOTE: force withdraw failure

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Withdrawable.WithdrawFailed.selector));
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);
    }

    function test_WhenWithdrawCallIsSuccessful()
        external
        whenCallerIsOwner
        whenShortcutExecutionFailed
        whenTokenInIsNativeToken
    {
        // Get shortcut
        // NOTE: force shortcut failure by replacing `EnsoShortcutsHelpers` address with Zero address
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1(address(s_weth), address(0), s_owner);

        vm.deal(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecutionFailed
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionFailed(hex"08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000284f6e6c79206f6e652072657475726e2076616c7565207065726d6974746564202873746174696329000000000000000000000000000000000000000000000000");
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should send native token amount to owner
        assertBalanceDiff(
            pre.receiverTokenIn, post.receiverTokenIn, int256(shortcut.amountsIn[0]), "Receiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.receiverTokenOut, post.receiverTokenOut, 0, "Receiver TokenOut (WETH)");
        assertBalanceDiff(pre.feeReceiverTokenIn, post.feeReceiverTokenIn, 0, "FeeReceiver TokenIn (ETH)");
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)");
    }

    modifier whenTokenInIsNotNativeToken() {
        _;
    }

    function test_WhenWithdrawSafeTransferIsUnsuccessful()
        external
        whenCallerIsOwner
        whenShortcutExecutionFailed
        whenTokenInIsNotNativeToken
    {
        // Get shortcut
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut2(
            address(s_weth), address(s_ensoShortcutsHelpers), s_owner, 0x6AA68C46eD86161eB318b1396F7b79E386e88676
        );

        // Top-up EnsoReceiver with WETH (as owner)
        s_weth.deposit{ value: shortcut.amountsIn[0] }(); // NOTE: as owner
        s_weth.transfer(address(s_ensoReceiver), shortcut.amountsIn[0] - 1);

        // it should revert
        vm.expectRevert(bytes(""), address(s_weth));
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);
    }

    function test_WhenWithdrawSafeTransferIsSuccessful()
        external
        whenCallerIsOwner
        whenShortcutExecutionFailed
        whenTokenInIsNotNativeToken
    {
        // Get shortcut
        // NOTE: force shortcut failure by replacing `EnsoShortcutsHelpers` address with Zero address
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut2(
            address(s_weth), address(0), s_owner, 0x6AA68C46eD86161eB318b1396F7b79E386e88676
        );

        // Top-up EnsoReceiver with WETH (as owner)
        s_weth.deposit{ value: shortcut.amountsIn[0] }(); // NOTE: as owner
        s_weth.transfer(address(s_ensoReceiver), shortcut.amountsIn[0]);

        // Get balances before execution
        Balances memory pre;
        pre.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        pre.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        pre.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        pre.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        pre.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        pre.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should emit ShortcutExecutionFailed
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.ShortcutExecutionFailed(hex"08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000284f6e6c79206f6e652072657475726e2076616c7565207065726d6974746564202873746174696329000000000000000000000000000000000000000000000000");
        s_ensoReceiver.safeExecute(IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData);

        // Get balances after execution
        Balances memory post;
        post.receiverTokenIn = balance(shortcut.tokensIn[0], shortcut.receiver);
        post.receiverTokenOut = balance(shortcut.tokensOut[0], shortcut.receiver);

        post.feeReceiverTokenIn = balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        post.feeReceiverTokenOut = balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        post.ensoReceiverTokenIn = balance(shortcut.tokensIn[0], address(s_ensoReceiver));
        post.ensoReceiverTokenOut = balance(shortcut.tokensOut[0], address(s_ensoReceiver));

        // it should transfer token amount to owner
        assertBalanceDiff(
            pre.receiverTokenIn, post.receiverTokenIn, int256(shortcut.amountsIn[0]), "Receiver TokenIn (WETH)"
        );
        assertBalanceDiff(pre.receiverTokenOut, post.receiverTokenOut, 0, "Receiver TokenOut (ETH)");
        assertBalanceDiff(pre.feeReceiverTokenIn, post.feeReceiverTokenIn, 0, "FeeReceiver TokenIn (WETH)");
        assertBalanceDiff(pre.feeReceiverTokenOut, post.feeReceiverTokenOut, 0, "FeeReceiver TokenOut (ETH)");
        assertBalanceDiff(
            pre.ensoReceiverTokenIn,
            post.ensoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (WETH)"
        );
        assertBalanceDiff(pre.ensoReceiverTokenOut, post.ensoReceiverTokenOut, 0, "EnsoReceiver TokenOut (ETH)");
    }
}

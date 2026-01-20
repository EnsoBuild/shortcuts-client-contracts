// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { IEnsoCCIPReceiver } from "../../../../../src/interfaces/IEnsoCCIPReceiver.sol";
import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";

contract EnsoCCIPReceiver_CcipReceive_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    address private s_caller;
    Client.Any2EVMMessage private s_message;

    function test_RevertWhen_CallerIsNotCcipRouter() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, s_account1));
        vm.prank(s_account1);
        s_ensoCcipReceiver.ccipReceive(s_message);
    }

    modifier whenCallerIsCcipRouter() {
        s_caller = address(s_ccipRouter);
        _;
    }

    function test_WhenMessageWasAlreadyExecuted() external whenCallerIsCcipRouter {
        // Arrange
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(s_tokenA), amount: 16 ether });

        s_message.destTokenAmounts = destTokenAmounts;
        s_message.data = abi.encode(s_account1, ""); // NOTE: no shortcut should succeed

        // Execute message for the first time
        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), s_message.destTokenAmounts[0].amount);
        vm.stopPrank();

        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.ALREADY_EXECUTED;
        bytes memory errorData;

        // Act & Assert
        vm.skip(true);
        vm.expectEmit(true, false, false, true);
        // it should emit MessageValidationFailed
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should not update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    modifier whenMessageWasNotExecuted() {
        _;
    }

    function test_WhenMessageHasNoTokens() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.NO_TOKENS;
        bytes memory errorData;

        address token;
        uint256 amount;
        address receiver;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageQuarantined(messageId, errorCode, token, amount, receiver);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    modifier whenMessageHasTokens() {
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](2);
        destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(s_tokenA), amount: amountA });
        destTokenAmounts[1] = Client.EVMTokenAmount({ token: address(s_tokenB), amount: amountB });

        s_message.destTokenAmounts = destTokenAmounts;
        _;
    }

    function test_WhenMessageHasMoreThanOneToken()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
    {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.TOO_MANY_TOKENS;
        bytes memory errorData;

        address token;
        uint256 amount;
        address receiver;

        uint256 ccipReceiverBalanceTokenABefore = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        uint256 ccipReceiverBalanceTokenBBefore = balance(address(s_tokenB), address(s_ensoCcipReceiver));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), s_message.destTokenAmounts[0].amount);
        s_tokenB.transfer(address(s_ensoCcipReceiver), s_message.destTokenAmounts[1].amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageQuarantined(messageId, errorCode, token, amount, receiver);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        uint256 ccipReceiverBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore,
            ccipReceiverBalanceTokenAAfter,
            int256(s_message.destTokenAmounts[0].amount),
            "EnsoCCIPReceiver tokenOut (TKNB)"
        );
        uint256 ccipReceiverBalanceTokenBAfter = balance(address(s_tokenB), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenBBefore,
            ccipReceiverBalanceTokenBAfter,
            int256(s_message.destTokenAmounts[1].amount),
            "EnsoCCIPReceiver tokenOut (TKNB)"
        );
    }

    modifier whenMessageHasSingleToken() {
        uint256 amountA = 0 ether;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(s_tokenA), amount: amountA });

        s_message.destTokenAmounts = destTokenAmounts;
        _;
    }

    function test_WhenMessageTokenAmountIsZero()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
    {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.NO_TOKEN_AMOUNT;
        bytes memory errorData;

        address token = s_message.destTokenAmounts[0].token;
        uint256 amount;
        address receiver;

        uint256 ccipReceiverBalanceTokenABefore = balance(address(s_tokenA), address(s_ensoCcipReceiver));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), s_message.destTokenAmounts[0].amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageQuarantined(messageId, errorCode, token, amount, receiver);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        uint256 ccipReceiverBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore,
            ccipReceiverBalanceTokenAAfter,
            int256(s_message.destTokenAmounts[0].amount),
            "EnsoCCIPReceiver tokenOut (TKNA)"
        );
    }

    modifier whenMessageTokenAmountIsGtZero() {
        uint256 amountA = 16 ether;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(s_tokenA), amount: amountA });

        s_message.destTokenAmounts = destTokenAmounts;
        _;
    }

    function test_WhenMessageDataIsMalformed()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
        whenMessageTokenAmountIsGtZero
    {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.MALFORMED_MESSAGE_DATA;
        bytes memory errorData;

        address token = s_message.destTokenAmounts[0].token;
        uint256 amount = s_message.destTokenAmounts[0].amount;
        address receiver;

        uint256 ccipReceiverBalanceTokenABefore = balance(address(s_tokenA), address(s_ensoCcipReceiver));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageQuarantined(messageId, errorCode, token, amount, receiver);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        uint256 ccipReceiverBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore,
            ccipReceiverBalanceTokenAAfter,
            int256(amount),
            "EnsoCCIPReceiver tokenOut (TKNA)"
        );
    }

    modifier whenMessageDataIsWellFormed() {
        s_message.data = abi.encode(address(0), "");
        _;
    }

    function test_WhenMessageDataReceiverIsZeroAddress()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
        whenMessageTokenAmountIsGtZero
        whenMessageDataIsWellFormed
    {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.ZERO_ADDRESS_RECEIVER;
        bytes memory errorData;

        address token = s_message.destTokenAmounts[0].token;
        uint256 amount = s_message.destTokenAmounts[0].amount;
        address receiver;

        uint256 ccipReceiverBalanceTokenABefore = balance(address(s_tokenA), address(s_ensoCcipReceiver));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageQuarantined(messageId, errorCode, token, amount, receiver);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        uint256 ccipReceiverBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore,
            ccipReceiverBalanceTokenAAfter,
            int256(amount),
            "EnsoCCIPReceiver tokenOut (TKNA)"
        );
    }

    modifier whenMessageDataReceiverIsNotZeroAddress() {
        s_message.data = abi.encode(s_account1, "");
        _;
    }

    function test_WhenContractIsPaused()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
        whenMessageTokenAmountIsGtZero
        whenMessageDataIsWellFormed
        whenMessageDataReceiverIsNotZeroAddress
    {
        // Arrange
        bytes32 messageId = s_message.messageId;
        IEnsoCCIPReceiver.ErrorCode errorCode = IEnsoCCIPReceiver.ErrorCode.PAUSED;
        bytes memory errorData;

        address token = s_message.destTokenAmounts[0].token;
        uint256 amount = s_message.destTokenAmounts[0].amount;
        (address receiver,) = abi.decode(s_message.data, (address, bytes));

        uint256 ccipReceiverBalanceTokenABefore = balance(token, address(s_ensoCcipReceiver));
        uint256 receiverBalanceTokenABefore = balance(token, receiver);

        vm.prank(s_owner);
        s_ensoCcipReceiver.pause();

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiver.MessageValidationFailed(messageId, errorCode, errorData);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer token amount to receiver
        uint256 ccipReceiverBalanceTokenAAfter = balance(token, address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore, ccipReceiverBalanceTokenAAfter, 0, "EnsoCCIPReceiver tokenOut (TKNA)"
        );
        uint256 receiverBalanceTokenAAfter = balance(token, receiver);
        assertBalanceDiff(
            receiverBalanceTokenABefore, receiverBalanceTokenAAfter, int256(amount), "Receiver tokenOut (TKNA)"
        );
    }

    modifier whenContractIsNotPaused() {
        // noop
        _;
    }

    function test_WhenShortcutExecutionSucceeded()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
        whenMessageTokenAmountIsGtZero
        whenMessageDataIsWellFormed
        whenMessageDataReceiverIsNotZeroAddress
        whenContractIsNotPaused
    {
        // Arrange
        // NOTE: this test uses a shortcut that unwraps 1 WETH and sends it to receiver as ETH (0.99 ETH). There is also
        // a 0.01 WETH fee sent to feeReceiver.
        address receiver = s_account1;
        address feeReceiver = s_account2;

        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut2(address(s_weth), address(s_ensoShortcutsHelpers), receiver, feeReceiver);
        s_message.data = abi.encode(s_account1, shortcut.txData);

        bytes32 messageId = s_message.messageId;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({ token: address(s_weth), amount: shortcut.amountsIn[0] });

        s_message.destTokenAmounts = destTokenAmounts;

        uint256 ccipReceiverBalanceEthBefore = balance(NATIVE_ASSET, address(s_ensoCcipReceiver));
        uint256 ccipReceiverBalanceWethBefore = balance(address(s_weth), address(s_ensoCcipReceiver));
        uint256 ensoShortcutsBalanceEthBefore = balance(NATIVE_ASSET, address(s_ensoShortcuts));
        uint256 ensoShortcutsBalanceWethBefore = balance(address(s_weth), address(s_ensoShortcuts));
        uint256 receiverBalanceEthBefore = balance(NATIVE_ASSET, receiver);
        uint256 receiverBalanceWethBefore = balance(address(s_weth), receiver);
        uint256 feeReceiverBalanceEthBefore = balance(NATIVE_ASSET, feeReceiver);
        uint256 feeReceiverBalanceWethBefore = balance(address(s_weth), feeReceiver);

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_weth.deposit{ value: shortcut.amountsIn[0] }();
        s_weth.transfer(address(s_ensoCcipReceiver), shortcut.amountsIn[0]);
        vm.stopPrank();

        // Act & Assert
        // it should emit ShortcutExecutionSuccessful
        vm.expectEmit(true, false, false, true);
        emit IEnsoCCIPReceiver.ShortcutExecutionSuccessful(messageId);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it shoud update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should apply shortcut state changes
        uint256 ccipReceiverBalanceEthAfter = balance(NATIVE_ASSET, address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceEthBefore, ccipReceiverBalanceEthAfter, 0, "EnsoCCIPReceiver tokenOut (ETH)"
        );
        uint256 ccipReceiverBalanceWethAfter = balance(address(s_weth), address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceWethBefore, ccipReceiverBalanceWethAfter, 0, "EnsoCCIPReceiver tokenIn (WETH)"
        );
        uint256 ensoShortcutsBalanceEthAfter = balance(NATIVE_ASSET, address(s_ensoShortcuts));
        assertBalanceDiff(
            ensoShortcutsBalanceEthBefore, ensoShortcutsBalanceEthAfter, 0, "EnsoShortcuts tokenOut (ETH)"
        );
        uint256 ensoShortcutsBalanceWethAfter = balance(address(s_weth), address(s_ensoShortcuts));
        assertBalanceDiff(
            ensoShortcutsBalanceWethBefore, ensoShortcutsBalanceWethAfter, 0, "EnsoShortcuts tokenIn (WETH)"
        );
        uint256 receiverBalanceEthAfter = balance(NATIVE_ASSET, receiver);
        assertBalanceDiff(
            receiverBalanceEthBefore,
            receiverBalanceEthAfter,
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver tokenOut (ETH)"
        );
        uint256 receiverBalanceWethAfter = balance(address(s_weth), receiver);
        assertBalanceDiff(receiverBalanceWethBefore, receiverBalanceWethAfter, 0, "Receiver tokenIn (WETH)");
        uint256 feeReceiverBalanceEthAfter = balance(NATIVE_ASSET, feeReceiver);
        assertBalanceDiff(feeReceiverBalanceEthBefore, feeReceiverBalanceEthAfter, 0, "FeeReceiver tokenOut(ETH)");
        uint256 feeReceiverBalanceWethAfter = balance(address(s_weth), feeReceiver);
        assertBalanceDiff(
            feeReceiverBalanceWethBefore, feeReceiverBalanceWethAfter, int256(shortcut.fee), "FeeReceiver tokenIn(WETH)"
        );
    }

    function test_WhenShortcutExecutionFailed()
        external
        whenCallerIsCcipRouter
        whenMessageWasNotExecuted
        whenMessageHasTokens
        whenMessageHasSingleToken
        whenMessageTokenAmountIsGtZero
        whenMessageDataIsWellFormed
        whenMessageDataReceiverIsNotZeroAddress
        whenContractIsNotPaused
    {
        // Arrange
        s_message.data = abi.encode(s_account1, "0xdeadbeef");

        bytes32 messageId = s_message.messageId;
        bytes memory errorData;

        address token = s_message.destTokenAmounts[0].token;
        uint256 amount = s_message.destTokenAmounts[0].amount;
        (address receiver,) = abi.decode(s_message.data, (address, bytes));

        uint256 ccipReceiverBalanceTokenABefore = balance(token, address(s_ensoCcipReceiver));
        uint256 receiverBalanceTokenABefore = balance(token, receiver);

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act & Assert
        // it should emit ShortcutExecutionFailed
        vm.expectEmit(true, false, false, true);
        emit IEnsoCCIPReceiver.ShortcutExecutionFailed(messageId, errorData);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it shoud update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer token amount to receiver
        uint256 ccipReceiverBalanceTokenAAfter = balance(token, address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore, ccipReceiverBalanceTokenAAfter, 0, "EnsoCCIPReceiver tokenOut (TKNA)"
        );
        uint256 receiverBalanceTokenAAfter = balance(token, receiver);
        assertBalanceDiff(
            receiverBalanceTokenABefore, receiverBalanceTokenAAfter, int256(amount), "Receiver tokenOut (TKNA)"
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoCCIPReceiverV2 } from "../../../../../src/interfaces/IEnsoCCIPReceiverV2.sol";
import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { ShortcutsEthereum } from "../../../../shortcuts/ShortcutsEthereum.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";

contract EnsoCCIPReceiverV2_CcipReceive_Unit_Concrete_Test is
    EnsoCCIPReceiverV2_Unit_Concrete_Test,
    TokenBalanceHelper
{
    address private s_caller;
    Client.Any2EVMMessage private s_message;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _setTokens(address[] memory tokens, uint256[] memory amounts) private {
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            destTokenAmounts[i] = Client.EVMTokenAmount({ token: tokens[i], amount: amounts[i] });
        }
        s_message.destTokenAmounts = destTokenAmounts;
    }

    function _deliver(address token, uint256 amount) private {
        vm.prank(s_deployer);
        // s_deployer holds TKNA/TKNB/TKNC; route through the right mock by address
        (bool ok,) =
            token.call(abi.encodeWithSignature("transfer(address,uint256)", address(s_ensoCcipReceiver), amount));
        require(ok, "deliver failed");
    }

    function _arr(address a) private pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _arr(address a, address b) private pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function _amt(uint256 a) private pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = a;
    }

    function _amt(uint256 a, uint256 b) private pure returns (uint256[] memory out) {
        out = new uint256[](2);
        out[0] = a;
        out[1] = b;
    }

    // -------------------------------------------------------------------------
    // caller gating
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // replay
    // -------------------------------------------------------------------------

    function test_WhenMessageWasAlreadyExecuted() external whenCallerIsCcipRouter {
        // Arrange
        _setTokens(_arr(address(s_tokenA)), _amt(16 ether));
        s_message.data = abi.encode(s_account1, ""); // empty shortcut succeeds

        // Execute message for the first time
        _deliver(address(s_tokenA), 16 ether);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.ALREADY_EXECUTED, abi.encode(messageId)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should keep executedMessage set
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    modifier whenMessageWasNotExecuted() {
        _;
    }

    // -------------------------------------------------------------------------
    // token shape
    // -------------------------------------------------------------------------

    function test_WhenMessageHasNoTokens() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(messageId, IEnsoCCIPReceiverV2.ErrorCode.NO_TOKENS, "");
        // it should emit MessageQuarantined (empty token/amount arrays)
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.NO_TOKENS, new address[](0), new uint256[](0), address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    function test_WhenMessageHasMoreThanMaxTokens() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange: 3 tokens > MAX_TOKENS (2)
        address[] memory tokens = new address[](3);
        tokens[0] = address(s_tokenA);
        tokens[1] = address(s_tokenB);
        tokens[2] = address(s_tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 16 ether;
        amounts[1] = 42 ether;
        amounts[2] = 7 ether;
        _setTokens(tokens, amounts);

        _deliver(address(s_tokenA), amounts[0]);
        _deliver(address(s_tokenB), amounts[1]);
        _deliver(address(s_tokenC), amounts[2]);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(messageId, IEnsoCCIPReceiverV2.ErrorCode.TOO_MANY_TOKENS, "");
        // it should emit MessageQuarantined (arrays not materialized past the cap check → empty)
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.TOO_MANY_TOKENS, new address[](0), new uint256[](0), address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), amounts[0], "escrow TKNA");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), amounts[1], "escrow TKNB");
        assertEq(balance(address(s_tokenC), address(s_ensoCcipReceiver)), amounts[2], "escrow TKNC");
    }

    // -------------------------------------------------------------------------
    // two tokens
    // -------------------------------------------------------------------------

    function test_WhenTokensAreDuplicated() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange: same token twice
        _setTokens(_arr(address(s_tokenA), address(s_tokenA)), _amt(16 ether, 42 ether));
        _deliver(address(s_tokenA), 58 ether);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(messageId, IEnsoCCIPReceiverV2.ErrorCode.DUPLICATE_TOKENS, "");
        // it should emit MessageQuarantined with both (duplicate) entries
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.DUPLICATE_TOKENS,
            _arr(address(s_tokenA), address(s_tokenA)),
            _amt(16 ether, 42 ether),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 58 ether, "escrow TKNA");
    }

    function test_WhenTwoTokensAndATokenAmountIsZero() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange: second token has zero amount
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(16 ether, 0));
        _deliver(address(s_tokenA), 16 ether);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed with the offending index
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.NO_TOKEN_AMOUNT, abi.encode(uint256(1))
        );
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.NO_TOKEN_AMOUNT,
            _arr(address(s_tokenA), address(s_tokenB)),
            _amt(16 ether, 0),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    function test_WhenTwoTokensDataIsMalformed() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(amountA, amountB));
        s_message.data = hex"deadbeef"; // too short to decode (address,bytes)

        _deliver(address(s_tokenA), amountA);
        _deliver(address(s_tokenB), amountB);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.MALFORMED_MESSAGE_DATA, ""
        );
        // it should emit MessageQuarantined with both entries
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.MALFORMED_MESSAGE_DATA,
            _arr(address(s_tokenA), address(s_tokenB)),
            _amt(amountA, amountB),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), amountA, "escrow TKNA");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), amountB, "escrow TKNB");
    }

    function test_WhenTwoTokensReceiverIsZeroAddress() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(amountA, amountB));
        s_message.data = abi.encode(address(0), "");

        _deliver(address(s_tokenA), amountA);
        _deliver(address(s_tokenB), amountB);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.ZERO_ADDRESS_RECEIVER, ""
        );
        // it should emit MessageQuarantined with both entries
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.ZERO_ADDRESS_RECEIVER,
            _arr(address(s_tokenA), address(s_tokenB)),
            _amt(amountA, amountB),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message tokens
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), amountA, "escrow TKNA");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), amountB, "escrow TKNB");
    }

    function test_WhenTwoTokensContractIsPaused() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;
        address receiver = s_account1;
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(amountA, amountB));
        s_message.data = abi.encode(receiver, "");

        vm.prank(s_owner);
        s_ensoCcipReceiver.pause();

        _deliver(address(s_tokenA), amountA);
        _deliver(address(s_tokenB), amountB);

        bytes32 messageId = s_message.messageId;
        uint256 receiverABefore = balance(address(s_tokenA), receiver);
        uint256 receiverBBefore = balance(address(s_tokenB), receiver);

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(messageId, IEnsoCCIPReceiverV2.ErrorCode.PAUSED, "");
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer both token amounts to receiver (via the _refundAll loop)
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNA)");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNB)");
        assertBalanceDiff(
            receiverABefore, balance(address(s_tokenA), receiver), int256(amountA), "Receiver tokenOut (TKNA)"
        );
        assertBalanceDiff(
            receiverBBefore, balance(address(s_tokenB), receiver), int256(amountB), "Receiver tokenOut (TKNB)"
        );
    }

    function test_WhenTwoTokensExecutionSucceeded() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(amountA, amountB));
        // NOTE: empty shortcut → routeMulti deposits both tokens into EnsoShortcuts
        s_message.data = abi.encode(s_account1, "");

        _deliver(address(s_tokenA), amountA);
        _deliver(address(s_tokenB), amountB);

        bytes32 messageId = s_message.messageId;

        uint256 shortcutsTokenABefore = balance(address(s_tokenA), address(s_ensoShortcuts));
        uint256 shortcutsTokenBBefore = balance(address(s_tokenB), address(s_ensoShortcuts));

        // Act & Assert
        // it should emit ShortcutExecutionSuccessful
        vm.expectEmit(true, false, false, true);
        emit IEnsoCCIPReceiverV2.ShortcutExecutionSuccessful(messageId);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should apply shortcut state changes (both tokens routed via routeMulti)
        assertBalanceDiff(
            shortcutsTokenABefore,
            balance(address(s_tokenA), address(s_ensoShortcuts)),
            int256(amountA),
            "EnsoShortcuts tokenIn (TKNA)"
        );
        assertBalanceDiff(
            shortcutsTokenBBefore,
            balance(address(s_tokenB), address(s_ensoShortcuts)),
            int256(amountB),
            "EnsoShortcuts tokenIn (TKNB)"
        );
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenIn (TKNA)");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenIn (TKNB)");
    }

    function test_WhenTwoTokensExecutionFailed() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;
        _setTokens(_arr(address(s_tokenA), address(s_tokenB)), _amt(amountA, amountB));
        // NOTE: bad shortcut payload → routeMulti reverts → both tokens refunded to receiver
        address receiver = s_account1;
        s_message.data = abi.encode(receiver, "0xdeadbeef");

        _deliver(address(s_tokenA), amountA);
        _deliver(address(s_tokenB), amountB);

        bytes32 messageId = s_message.messageId;

        uint256 receiverTokenABefore = balance(address(s_tokenA), receiver);
        uint256 receiverTokenBBefore = balance(address(s_tokenB), receiver);

        // Act & Assert
        // it should emit ShortcutExecutionFailed
        vm.expectEmit(true, false, false, false);
        emit IEnsoCCIPReceiverV2.ShortcutExecutionFailed(messageId, "");
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer both token amounts to receiver
        assertBalanceDiff(
            receiverTokenABefore, balance(address(s_tokenA), receiver), int256(amountA), "Receiver tokenOut (TKNA)"
        );
        assertBalanceDiff(
            receiverTokenBBefore, balance(address(s_tokenB), receiver), int256(amountB), "Receiver tokenOut (TKNB)"
        );
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNA)");
        assertEq(balance(address(s_tokenB), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNB)");
    }

    // -------------------------------------------------------------------------
    // single token
    // -------------------------------------------------------------------------

    function test_WhenSingleTokenAmountIsZero() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        _setTokens(_arr(address(s_tokenA)), _amt(0));

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed with index 0
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.NO_TOKEN_AMOUNT, abi.encode(uint256(0))
        );
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.NO_TOKEN_AMOUNT, _arr(address(s_tokenA)), _amt(0), address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));
    }

    function test_WhenSingleTokenDataIsMalformed() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amount = 16 ether;
        _setTokens(_arr(address(s_tokenA)), _amt(amount));
        s_message.data = hex"deadbeef"; // too short to decode (address,bytes)

        _deliver(address(s_tokenA), amount);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.MALFORMED_MESSAGE_DATA, ""
        );
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.MALFORMED_MESSAGE_DATA,
            _arr(address(s_tokenA)),
            _amt(amount),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message token
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), amount, "escrow TKNA");
    }

    function test_WhenSingleTokenReceiverIsZeroAddress() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amount = 16 ether;
        _setTokens(_arr(address(s_tokenA)), _amt(amount));
        s_message.data = abi.encode(address(0), "");

        _deliver(address(s_tokenA), amount);

        bytes32 messageId = s_message.messageId;

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(
            messageId, IEnsoCCIPReceiverV2.ErrorCode.ZERO_ADDRESS_RECEIVER, ""
        );
        // it should emit MessageQuarantined
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageQuarantined(
            messageId,
            IEnsoCCIPReceiverV2.ErrorCode.ZERO_ADDRESS_RECEIVER,
            _arr(address(s_tokenA)),
            _amt(amount),
            address(0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should escrow message token
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), amount, "escrow TKNA");
    }

    function test_WhenSingleTokenContractIsPaused() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amount = 16 ether;
        address receiver = s_account1;
        _setTokens(_arr(address(s_tokenA)), _amt(amount));
        s_message.data = abi.encode(receiver, "");

        vm.prank(s_owner);
        s_ensoCcipReceiver.pause();

        _deliver(address(s_tokenA), amount);

        bytes32 messageId = s_message.messageId;
        uint256 receiverBefore = balance(address(s_tokenA), receiver);

        // Act & Assert
        // it should emit MessageValidationFailed
        vm.expectEmit(true, true, false, true);
        emit IEnsoCCIPReceiverV2.MessageValidationFailed(messageId, IEnsoCCIPReceiverV2.ErrorCode.PAUSED, "");
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer token amount to receiver
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNA)");
        assertBalanceDiff(
            receiverBefore, balance(address(s_tokenA), receiver), int256(amount), "Receiver tokenOut (TKNA)"
        );
    }

    function test_WhenSingleTokenExecutionSucceeded() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        // NOTE: shortcut unwraps 1 WETH and sends 0.99 ETH to receiver, 0.01 WETH fee to feeReceiver
        address receiver = s_account1;
        address feeReceiver = s_account2;

        Shortcut memory shortcut =
            ShortcutsEthereum.getShortcut2(address(s_weth), address(s_ensoShortcutsHelpers), receiver, feeReceiver);
        s_message.data = abi.encode(receiver, shortcut.txData);

        _setTokens(_arr(address(s_weth)), _amt(shortcut.amountsIn[0]));

        bytes32 messageId = s_message.messageId;

        uint256 receiverEthBefore = balance(NATIVE_ASSET, receiver);
        uint256 feeReceiverWethBefore = balance(address(s_weth), feeReceiver);

        // NOTE: deliver WETH to the receiver to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_weth.deposit{ value: shortcut.amountsIn[0] }();
        s_weth.transfer(address(s_ensoCcipReceiver), shortcut.amountsIn[0]);
        vm.stopPrank();

        // Act & Assert
        // it should emit ShortcutExecutionSuccessful
        vm.expectEmit(true, false, false, true);
        emit IEnsoCCIPReceiverV2.ShortcutExecutionSuccessful(messageId);
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should apply shortcut state changes
        assertEq(balance(address(s_weth), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenIn (WETH)");
        assertBalanceDiff(
            receiverEthBefore,
            balance(NATIVE_ASSET, receiver),
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver tokenOut (ETH)"
        );
        assertBalanceDiff(
            feeReceiverWethBefore,
            balance(address(s_weth), feeReceiver),
            int256(shortcut.fee),
            "FeeReceiver tokenIn (WETH)"
        );
    }

    function test_WhenSingleTokenExecutionFailed() external whenCallerIsCcipRouter whenMessageWasNotExecuted {
        // Arrange
        uint256 amount = 16 ether;
        address receiver = s_account1;
        _setTokens(_arr(address(s_tokenA)), _amt(amount));
        s_message.data = abi.encode(receiver, "0xdeadbeef");

        _deliver(address(s_tokenA), amount);

        bytes32 messageId = s_message.messageId;
        uint256 receiverBefore = balance(address(s_tokenA), receiver);

        // Act & Assert
        // it should emit ShortcutExecutionFailed
        vm.expectEmit(true, false, false, false);
        emit IEnsoCCIPReceiverV2.ShortcutExecutionFailed(messageId, "");
        vm.prank(s_caller);
        s_ensoCcipReceiver.ccipReceive(s_message);

        // it should update executedMessage
        assertTrue(s_ensoCcipReceiver.wasMessageExecuted(messageId));

        // it should safe transfer token amount to receiver
        assertEq(balance(address(s_tokenA), address(s_ensoCcipReceiver)), 0, "EnsoCCIPReceiver tokenOut (TKNA)");
        assertBalanceDiff(
            receiverBefore, balance(address(s_tokenA), receiver), int256(amount), "Receiver tokenOut (TKNA)"
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractMultiSend } from "../../../../../src/AbstractMultiSend.sol";
import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std/Test.sol";

contract EnsoReceiver_ExecuteMultiSend_SenderIsEnsoReceiver_Unit_Concrete_Test is
    EnsoReceiver_Unit_Concrete_Test,
    TokenBalanceHelper
{
    enum OperationType {
        CALL,
        DELEGATECALL,
        UNKNOWN
    }

    OperationType s_operationType = OperationType.UNKNOWN;

    function test_RevertWhen_Reentrant() external {
        uint256 amount = 1 ether;
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");
        // NOTE: calldata to deposit ETH into WETH
        bytes memory depositToWethTransaction =
            hex"00de09e74d4888bc4e65f589e8c13bce9f71ddf4c70000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000004d0e30db0";
        vm.deal(address(s_ensoReceiver), amount);

        bytes memory tx1Calldata =
            abi.encodeCall(s_ensoReceiver.executeMultiSend, (accountId, requestId, depositToWethTransaction));
        bytes memory transactions = bytes.concat(
            bytes1(uint8(OperationType.CALL)), // operation = call (0)
            bytes20(address(s_ensoReceiver)), // to
            bytes32(uint256(amount)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.prank(address(s_ensoReceiver));
        vm.expectRevert(bytes("ReentrancyGuardReentrantCall()"), address(s_ensoReceiver));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenNonReentrant() {
        _;
    }

    function test_RevertWhen_CallerIsNotEnsoReceiverNorOwner() external whenNonReentrant {
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes memory transactions;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenCallerIsEnsoReceiver() {
        vm.startPrank(address(s_ensoReceiver));
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_TransactionIsDelegatecall() external whenNonReentrant whenCallerIsEnsoReceiver {
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(OperationType.DELEGATECALL)), // operation = delegatecall (1)
            bytes20(address(s_weth)), // to
            bytes32(uint256(1 ether)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.expectRevert(bytes(""), address(s_ensoReceiver));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenTransactionIsCall() {
        s_operationType = OperationType.CALL; // operation = call (0)
        _;
    }

    function test_RevertWhen_CallFailed() external whenNonReentrant whenCallerIsEnsoReceiver whenTransactionIsCall {
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(s_operationType)), // operation = call (0)
            bytes20(address(s_weth)), // to
            bytes32(uint256(1 ether)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.expectRevert(bytes(""), address(s_weth));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    function test_WhenCallSucceeded() external whenNonReentrant whenCallerIsEnsoReceiver whenTransactionIsCall {
        uint256 amount = 1 ether;
        vm.deal(address(s_ensoReceiver), amount);

        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(s_operationType)), // operation = call (0)
            bytes20(address(s_weth)), // to
            bytes32(uint256(amount)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );
        console2.logBytes(transactions);

        // Get balances before withdrawal
        uint256 ensoReceiverBalanceEthPre = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceWethPre = balance(address(s_weth), address(s_ensoReceiver));

        // it should emit MultiSendExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractMultiSend.MultiSendExecuted(accountId, requestId);
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);

        // Get balances after withdrawal
        uint256 ensoReceiverBalanceEthPost = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceWethPost = balance(address(s_weth), address(s_ensoReceiver));

        // it should apply state changes
        assertBalanceDiff(
            ensoReceiverBalanceEthPre, ensoReceiverBalanceEthPost, -int256(amount), "EnsoReceiver NATIVE ASSET"
        );
        assertBalanceDiff(ensoReceiverBalanceWethPre, ensoReceiverBalanceWethPost, int256(amount), "EnsoReceiver WETH");
    }
}

contract EnsoReceiver_ExecuteMultiSend_SenderIsOwner_Unit_Concrete_Test is
    EnsoReceiver_Unit_Concrete_Test,
    TokenBalanceHelper
{
    enum OperationType {
        CALL,
        DELEGATECALL,
        UNKNOWN
    }

    OperationType s_operationType = OperationType.UNKNOWN;

    function test_RevertWhen_Reentrant() external {
        uint256 amount = 1 ether;
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");
        // NOTE: calldata to deposit ETH into WETH
        bytes memory depositToWethTransaction =
            hex"00de09e74d4888bc4e65f589e8c13bce9f71ddf4c70000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000004d0e30db0";
        vm.deal(address(s_ensoReceiver), amount);

        bytes memory tx1Calldata =
            abi.encodeCall(s_ensoReceiver.executeMultiSend, (accountId, requestId, depositToWethTransaction));
        bytes memory transactions = bytes.concat(
            bytes1(uint8(OperationType.CALL)), // operation = call (0)
            bytes20(address(s_ensoReceiver)), // to
            bytes32(uint256(amount)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.prank(address(s_owner));
        vm.expectRevert(bytes("ReentrancyGuardReentrantCall()"), address(s_ensoReceiver));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenNonReentrant() {
        _;
    }

    function test_RevertWhen_CallerIsNotEnsoReceiverNorOwner() external whenNonReentrant {
        bytes32 accountId = bytes32(0);
        bytes32 requestId = bytes32(0);
        bytes memory transactions;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(s_owner));
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_TransactionIsDelegatecall() external whenNonReentrant whenCallerIsOwner {
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(OperationType.DELEGATECALL)), // operation = delegatecall (1)
            bytes20(address(s_weth)), // to
            bytes32(uint256(1 ether)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.expectRevert(bytes(""), address(s_ensoReceiver));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    modifier whenTransactionIsCall() {
        s_operationType = OperationType.CALL; // operation = call (0)
        _;
    }

    function test_RevertWhen_CallFailed() external whenNonReentrant whenCallerIsOwner whenTransactionIsCall {
        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(s_operationType)), // operation = call (0)
            bytes20(address(s_weth)), // to
            bytes32(uint256(1 ether)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // it should revert
        vm.expectRevert(bytes(""), address(s_weth));
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);
    }

    function test_WhenCallSucceeded() external whenNonReentrant whenCallerIsOwner whenTransactionIsCall {
        uint256 amount = 1 ether;
        vm.deal(address(s_ensoReceiver), amount);

        bytes32 accountId = keccak256("user1");
        bytes32 requestId = keccak256("req1");

        bytes memory tx1Calldata = abi.encodeCall(s_weth.deposit, ());
        bytes memory transactions = bytes.concat(
            bytes1(uint8(s_operationType)), // operation = call (0)
            bytes20(address(s_weth)), // to
            bytes32(uint256(amount)), // value
            bytes32(uint256(tx1Calldata.length)), // data length
            tx1Calldata // data
        );

        // Get balances before withdrawal
        uint256 ensoReceiverBalanceEthPre = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceWethPre = balance(address(s_weth), address(s_ensoReceiver));

        // it should emit MultiSendExecuted
        vm.expectEmit(address(s_ensoReceiver));
        emit AbstractMultiSend.MultiSendExecuted(accountId, requestId);
        s_ensoReceiver.executeMultiSend(accountId, requestId, transactions);

        // Get balances after withdrawal
        uint256 ensoReceiverBalanceEthPost = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceWethPost = balance(address(s_weth), address(s_ensoReceiver));

        // it should apply state changes
        assertBalanceDiff(
            ensoReceiverBalanceEthPre, ensoReceiverBalanceEthPost, -int256(amount), "EnsoReceiver NATIVE ASSET"
        );
        assertBalanceDiff(ensoReceiverBalanceWethPre, ensoReceiverBalanceWethPost, int256(amount), "EnsoReceiver WETH");
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCTPExecutor } from "../../../../../src/bridge/EnsoCCTPExecutor.sol";
import { IEnsoCCTPExecutor } from "../../../../../src/interfaces/IEnsoCCTPExecutor.sol";
import { IMessageTransmitterV2 } from "../../../../../src/vendor/cctp/interfaces/IMessageTransmitterV2.sol";
import { ITokenMessengerV2 } from "../../../../../src/vendor/cctp/interfaces/ITokenMessengerV2.sol";
import {
    MockMessageTransmitterV2,
    MockTokenMessengerV2,
    MockTokenMinterV2
} from "../../../../mocks/MockCctpContracts.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockEnsoRouter } from "../../../../mocks/MockEnsoRouter.sol";
import { Test } from "forge-std/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

/// @dev A router stand-in whose callback consumes all forwarded gas, used to prove the executor's
///      reserved refund gas keeps the catch-refund path executable even under a gas-exhausting callback.
contract GasBurnerRouter {
    function shortcuts() external view returns (address) {
        return address(this);
    }

    fallback() external payable {
        assembly {
            for { } 1 { } { mstore(0x0, keccak256(0x0, 0x20)) }
        }
    }

    receive() external payable { }
}

contract EnsoCCTPExecutorTest is Test {
    uint32 private constant MESSAGE_VERSION = 1;
    uint32 private constant BURN_MESSAGE_VERSION = 1;
    uint256 private constant BURN_AMOUNT = 100e6;
    uint256 private constant CIRCLE_FEE = 1e6;
    uint256 private constant MINT_AMOUNT = BURN_AMOUNT - CIRCLE_FEE;
    uint256 private constant EXECUTION_FEE = 4e6;
    uint256 private constant GAS_FOR_REFUND = 100_000;
    bytes32 private constant REQUEST_ID = keccak256("request");

    address private s_owner;
    address private s_submitter;
    address private s_refundReceiver;
    address private s_recoveryReceiver;
    MockERC20 private s_usdc;
    MockMessageTransmitterV2 private s_messageTransmitter;
    MockTokenMessengerV2 private s_tokenMessenger;
    MockEnsoRouter private s_router;
    EnsoCCTPExecutor private s_executor;

    function setUp() external {
        s_owner = makeAddr("owner");
        s_submitter = makeAddr("submitter");
        s_refundReceiver = makeAddr("refundReceiver");
        s_recoveryReceiver = makeAddr("recoveryReceiver");

        s_usdc = new MockERC20("USD Coin", "USDC");
        s_messageTransmitter = new MockMessageTransmitterV2(address(s_usdc), MESSAGE_VERSION);
        MockTokenMinterV2 tokenMinter = new MockTokenMinterV2(address(s_usdc));
        s_tokenMessenger =
            new MockTokenMessengerV2(address(s_messageTransmitter), address(tokenMinter), BURN_MESSAGE_VERSION);
        s_router = new MockEnsoRouter();
        s_executor = new EnsoCCTPExecutor(
            s_owner,
            IMessageTransmitterV2(address(s_messageTransmitter)),
            ITokenMessengerV2(address(s_tokenMessenger)),
            address(s_usdc),
            address(s_router),
            MESSAGE_VERSION,
            BURN_MESSAGE_VERSION,
            GAS_FOR_REFUND
        );
    }

    function test_ExecuteRoutesMintedAmountAndPaysSubmitter() external {
        bytes memory callbackData = abi.encodeCall(MockEnsoRouter.setRouteSingleResponse, (true, ""));
        bytes memory message = _message(
            address(s_tokenMessenger), address(s_executor), address(s_executor), _callback(EXECUTION_FEE, callbackData)
        );

        vm.expectCall(address(s_router), callbackData);
        vm.expectEmit(true, true, false, true, address(s_executor));
        emit IEnsoCCTPExecutor.ShortcutExecutionSuccessful(REQUEST_ID, s_submitter, MINT_AMOUNT, EXECUTION_FEE);
        vm.prank(s_submitter);
        s_executor.execute(message, "attestation");

        assertEq(s_usdc.balanceOf(s_submitter), EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(s_router.shortcuts()), MINT_AMOUNT - EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
    }

    function test_ExecuteRefundsWhenRouterCallFails() external {
        bytes memory callbackData = hex"deadbeef";
        bytes memory message = _message(
            address(s_tokenMessenger), address(s_executor), address(s_executor), _callback(EXECUTION_FEE, callbackData)
        );

        vm.expectCall(address(s_router), callbackData);
        vm.expectEmit(true, true, false, true, address(s_executor));
        emit IEnsoCCTPExecutor.ShortcutExecutionFailed(
            REQUEST_ID, s_submitter, s_refundReceiver, MINT_AMOUNT - EXECUTION_FEE, EXECUTION_FEE
        );
        vm.prank(s_submitter);
        s_executor.execute(message, "attestation");

        assertEq(s_usdc.balanceOf(s_submitter), EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(s_refundReceiver), MINT_AMOUNT - EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(s_router.shortcuts()), 0);
        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
    }

    function test_RevertWhen_ExecutionFeeExceedsMintAmount() external {
        uint256 executionFee = MINT_AMOUNT + 1;
        bytes memory message = _message(
            address(s_tokenMessenger), address(s_executor), address(s_executor), _callback(executionFee, "")
        );

        vm.expectRevert(
            abi.encodeWithSelector(IEnsoCCTPExecutor.ExecutionFeeExceedsMintAmount.selector, executionFee, MINT_AMOUNT)
        );
        vm.prank(s_submitter);
        s_executor.execute(message, "attestation");

        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
        assertEq(s_usdc.balanceOf(s_submitter), 0);
    }

    /// @dev The check is `>=`: a fee equal to the mint leaves nothing to route, so it must revert too
    ///      (boundary of the fee < mint invariant, not just fee > mint).
    function test_RevertWhen_ExecutionFeeEqualsMintAmount() external {
        uint256 executionFee = MINT_AMOUNT;
        bytes memory message = _message(
            address(s_tokenMessenger), address(s_executor), address(s_executor), _callback(executionFee, "")
        );

        vm.expectRevert(
            abi.encodeWithSelector(IEnsoCCTPExecutor.ExecutionFeeExceedsMintAmount.selector, executionFee, MINT_AMOUNT)
        );
        vm.prank(s_submitter);
        s_executor.execute(message, "attestation");

        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
        assertEq(s_usdc.balanceOf(s_submitter), 0);
    }

    function test_ExecuteRejectsInvalidCctpRoutingFields() external {
        bytes memory callback = _callback(0, "");
        address invalidAddress = makeAddr("invalidAddress");

        vm.expectRevert(abi.encodeWithSelector(IEnsoCCTPExecutor.InvalidMessageRecipient.selector, invalidAddress));
        s_executor.execute(_message(invalidAddress, address(s_executor), address(s_executor), callback), "attestation");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnsoCCTPExecutor.InvalidDestinationCaller.selector, bytes32(uint256(uint160(invalidAddress)))
            )
        );
        s_executor.execute(
            _message(address(s_tokenMessenger), invalidAddress, address(s_executor), callback), "attestation"
        );

        vm.expectRevert(abi.encodeWithSelector(IEnsoCCTPExecutor.InvalidMintRecipient.selector, invalidAddress));
        s_executor.execute(
            _message(address(s_tokenMessenger), address(s_executor), invalidAddress, callback), "attestation"
        );
    }

    function test_ExecuteWithoutCallbackTransfersFullMintToRecoveryReceiver() external {
        bytes memory message = _message(address(1), address(2), address(3), "");

        vm.prank(s_owner);
        s_executor.executeWithoutCallback(message, "attestation", s_recoveryReceiver);

        assertEq(s_usdc.balanceOf(s_recoveryReceiver), MINT_AMOUNT);
        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
    }

    function test_RevertWhen_ExecuteWithoutCallbackCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_submitter));
        vm.prank(s_submitter);
        s_executor.executeWithoutCallback("", "", s_recoveryReceiver);
    }

    function test_RecoverTokensTransfersRequestedAmount() external {
        uint256 amount = 10e6;
        s_usdc.mint(address(s_executor), amount);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_submitter));
        vm.prank(s_submitter);
        s_executor.recoverTokens(address(s_usdc), s_recoveryReceiver, amount);

        vm.prank(s_owner);
        s_executor.recoverTokens(address(s_usdc), s_recoveryReceiver, amount);

        assertEq(s_usdc.balanceOf(s_recoveryReceiver), amount);
        assertEq(s_usdc.balanceOf(address(s_executor)), 0);
    }

    function test_PauseBlocksExecuteUntilOwnerUnpauses() external {
        bytes memory callbackData = abi.encodeCall(MockEnsoRouter.setRouteSingleResponse, (true, ""));
        bytes memory message =
            _message(address(s_tokenMessenger), address(s_executor), address(s_executor), _callback(0, callbackData));

        vm.prank(s_owner);
        s_executor.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        s_executor.execute(message, "attestation");

        vm.prank(s_owner);
        s_executor.unpause();
        s_executor.execute(message, "attestation");

        assertEq(s_usdc.balanceOf(s_router.shortcuts()), MINT_AMOUNT);
    }

    function test_RevertWhen_ExecuteCallbackCallerIsNotExecutor() external {
        vm.expectRevert(IEnsoCCTPExecutor.NotSelf.selector);
        s_executor.executeCallback(0, "");
    }

    /// @dev A callback that burns all forwarded gas must still leave enough reserved for the catch to
    ///      refund the receiver, rather than propagating an out-of-gas that reverts the whole message.
    function test_RefundRunsEvenWhenCallbackExhaustsForwardedGas() external {
        GasBurnerRouter burner = new GasBurnerRouter();
        EnsoCCTPExecutor executor = new EnsoCCTPExecutor(
            s_owner,
            IMessageTransmitterV2(address(s_messageTransmitter)),
            ITokenMessengerV2(address(s_tokenMessenger)),
            address(s_usdc),
            address(burner),
            MESSAGE_VERSION,
            BURN_MESSAGE_VERSION,
            GAS_FOR_REFUND
        );

        bytes memory message = _message(
            address(s_tokenMessenger), address(executor), address(executor), _callback(EXECUTION_FEE, hex"deadbeef")
        );

        vm.expectEmit(true, true, false, true, address(executor));
        emit IEnsoCCTPExecutor.ShortcutExecutionFailed(
            REQUEST_ID, s_submitter, s_refundReceiver, MINT_AMOUNT - EXECUTION_FEE, EXECUTION_FEE
        );
        vm.prank(s_submitter);
        executor.execute{ gas: 2_000_000 }(message, "attestation");

        assertEq(s_usdc.balanceOf(s_refundReceiver), MINT_AMOUNT - EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(s_submitter), EXECUTION_FEE);
        assertEq(s_usdc.balanceOf(address(executor)), 0);
    }

    /// @dev The destination-caller field is a full 32-byte word; only the low 20 bytes carry the
    ///      address. A correct validator must reject any message whose high 12 bytes are non-zero,
    ///      even when the low 20 bytes match this contract. Circle enforces this too, but our check
    ///      must not rely on that.
    function testFuzz_RevertWhen_DestinationCallerHasDirtyHighBytes(bytes12 rubbish) external {
        vm.assume(rubbish != bytes12(0));
        bytes32 pollutedCaller = bytes32(rubbish) | bytes32(uint256(uint160(address(s_executor))));

        bytes memory message = _messageWithRawDestinationCaller(
            address(s_tokenMessenger), pollutedCaller, address(s_executor), _callback(0, "")
        );

        vm.expectRevert(abi.encodeWithSelector(IEnsoCCTPExecutor.InvalidDestinationCaller.selector, pollutedCaller));
        s_executor.execute(message, "attestation");
    }

    function _callback(uint256 executionFee, bytes memory callbackData) private view returns (bytes memory) {
        return abi.encode(
            IEnsoCCTPExecutor.CctpCallback({
                magic: s_executor.HOOK_MAGIC(),
                version: s_executor.HOOK_VERSION(),
                requestId: REQUEST_ID,
                refundReceiver: s_refundReceiver,
                executionFee: executionFee,
                estimatedGas: 0,
                callbackData: callbackData
            })
        );
    }

    function _message(
        address messageRecipient,
        address destinationCaller,
        address mintRecipient,
        bytes memory hookData
    )
        private
        pure
        returns (bytes memory)
    {
        return _messageWithRawDestinationCaller(
            messageRecipient, bytes32(uint256(uint160(destinationCaller))), mintRecipient, hookData
        );
    }

    /// @dev Same as {_message} but takes the destination-caller as a raw 32-byte word so tests can
    ///      inject dirty high bytes.
    function _messageWithRawDestinationCaller(
        address messageRecipient,
        bytes32 destinationCaller,
        address mintRecipient,
        bytes memory hookData
    )
        private
        pure
        returns (bytes memory)
    {
        bytes memory burnMessage = abi.encodePacked(
            BURN_MESSAGE_VERSION,
            bytes32(uint256(uint160(address(0xA11CE)))),
            bytes32(uint256(uint160(mintRecipient))),
            BURN_AMOUNT,
            bytes32(uint256(uint160(address(0xB0B)))),
            CIRCLE_FEE,
            CIRCLE_FEE,
            uint256(1),
            hookData
        );

        return abi.encodePacked(
            MESSAGE_VERSION,
            uint32(1),
            uint32(2),
            bytes32(uint256(1)),
            bytes32(uint256(uint160(address(0xCAFE)))),
            bytes32(uint256(uint160(messageRecipient))),
            destinationCaller,
            uint32(1000),
            uint32(1000),
            burnMessage
        );
    }
}

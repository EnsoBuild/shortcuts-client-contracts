// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoCCTPExecutor } from "../interfaces/IEnsoCCTPExecutor.sol";
import { IEnsoRouter } from "../interfaces/IEnsoRouter.sol";
import { IMessageTransmitterV2 } from "../vendor/cctp/interfaces/IMessageTransmitterV2.sol";
import { ITokenMessengerV2 } from "../vendor/cctp/interfaces/ITokenMessengerV2.sol";
import { BurnMessageV2 } from "../vendor/cctp/libraries/BurnMessageV2.sol";
import { MessageV2 } from "../vendor/cctp/libraries/MessageV2.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

contract EnsoCCTPExecutor is IEnsoCCTPExecutor, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    bytes4 public constant override HOOK_MAGIC = 0x454e534f; // ascii-encoded "ENSO"
    uint8 public constant override HOOK_VERSION = 1;

    IMessageTransmitterV2 public immutable override MESSAGE_TRANSMITTER;
    ITokenMessengerV2 public immutable override TOKEN_MESSENGER;
    IERC20 public immutable override USDC;
    address public immutable override ROUTER;
    address public immutable override SHORTCUTS;
    uint32 public immutable override SUPPORTED_MESSAGE_VERSION;
    uint32 public immutable override SUPPORTED_BURN_MESSAGE_VERSION;

    /// @dev Gas reserved from the callback so the catch-refund in `execute` is always executable
    ///      (USDC.safeTransfer to the refund receiver + the ShortcutExecutionFailed emit). Set per
    ///      deployment: opcode/state costs differ across CCTP chains, so validate on each chain's fork
    ///      (real native USDC, cold refund receiver, plus margin) and bias high — under-reserving makes
    ///      the refund itself revert.
    uint256 public immutable override GAS_FOR_REFUND;

    constructor(
        address owner_,
        IMessageTransmitterV2 messageTransmitter_,
        ITokenMessengerV2 tokenMessenger_,
        address usdc_,
        address router_,
        uint32 supportedMessageVersion_,
        uint32 supportedBurnMessageVersion_,
        uint256 gasForRefund_
    )
        Ownable(owner_)
    {
        // Only usdc_ needs an explicit zero-check: it is stored without any further validation. The
        // messenger, transmitter and router are each consumed below by external calls / cross-checks
        // that already revert on a zero (or non-contract) address.
        if (usdc_ == address(0)) {
            revert ZeroAddress();
        }

        if (address(messageTransmitter_) != tokenMessenger_.localMessageTransmitter()) {
            revert InvalidMessageTransmitter(address(messageTransmitter_));
        }
        if (supportedMessageVersion_ != messageTransmitter_.version()) {
            revert UnsupportedMessageVersion(supportedMessageVersion_);
        }
        if (supportedBurnMessageVersion_ != tokenMessenger_.messageBodyVersion()) {
            revert UnsupportedBurnMessageVersion(supportedBurnMessageVersion_);
        }

        address shortcuts_ = IEnsoRouter(router_).shortcuts();
        if (shortcuts_ == address(0)) {
            revert ZeroAddress();
        }

        MESSAGE_TRANSMITTER = messageTransmitter_;
        TOKEN_MESSENGER = tokenMessenger_;
        USDC = IERC20(usdc_);
        ROUTER = router_;
        SHORTCUTS = shortcuts_;
        SUPPORTED_MESSAGE_VERSION = supportedMessageVersion_;
        SUPPORTED_BURN_MESSAGE_VERSION = supportedBurnMessageVersion_;
        GAS_FOR_REFUND = gasForRefund_;
    }

    function execute(bytes calldata message, bytes calldata attestation) external whenNotPaused {
        bytes calldata hookData = _validateCctpMessage(message);
        CctpCallback memory callback = _decodeCallback(hookData);
        uint256 mintAmount = _mintThroughCctp(message, attestation);

        if (callback.executionFee >= mintAmount) {
            revert ExecutionFeeExceedsMintAmount(callback.executionFee, mintAmount);
        }
        uint256 callbackAmount = mintAmount - callback.executionFee;

        if (callback.executionFee != 0) {
            USDC.safeTransfer(msg.sender, callback.executionFee);
        }

        // Reserve gas for the catch-refund below so it is always executable, then hand the callback the
        // remainder. EIP-150 lets the EVM withhold 1/64 of gas on a call, so estimatedGas is checked
        // against what the callback will actually receive rather than raw gasleft(). estimatedGas is a
        // floor that stays inert (0) until the source-side hook encoder populates it; its exact
        // accounting (the inner router hop's own 1/64 + the SHORTCUTS transfer) must be reconciled with
        // the backend estimate when that lands.
        uint256 availableGas = gasleft();
        if (availableGas < GAS_FOR_REFUND) {
            revert InsufficientGas(callback.requestId, callback.estimatedGas, availableGas);
        }
        uint256 gasForCallback = availableGas - GAS_FOR_REFUND;
        if (gasForCallback - gasForCallback / 64 < callback.estimatedGas) {
            revert InsufficientGas(callback.requestId, callback.estimatedGas, availableGas);
        }

        try this.executeCallback{ gas: gasForCallback }(callbackAmount, callback.callbackData) {
            emit ShortcutExecutionSuccessful(callback.requestId, msg.sender, mintAmount, callback.executionFee);
        } catch {
            USDC.safeTransfer(callback.refundReceiver, callbackAmount);
            emit ShortcutExecutionFailed(
                callback.requestId, msg.sender, callback.refundReceiver, callbackAmount, callback.executionFee
            );
        }
    }

    function executeCallback(uint256 callbackAmount, bytes calldata callbackData) external {
        if (msg.sender != address(this)) {
            revert NotSelf();
        }
        USDC.safeTransfer(SHORTCUTS, callbackAmount);
        if (!_callRouter(callbackData)) {
            revert RouterCallFailed();
        }
    }

    function executeWithoutCallback(
        bytes calldata message,
        bytes calldata attestation,
        address receiver
    )
        external
        onlyOwner
    {
        _validateRecoveryReceiver(receiver);
        uint256 mintAmount = _mintThroughCctp(message, attestation);

        USDC.safeTransfer(receiver, mintAmount);
        emit CctpMessageRecovered(receiver, mintAmount);
    }

    function recoverTokens(address token, address receiver, uint256 amount) external onlyOwner {
        if (token == address(0) || receiver == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(receiver, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // executeWithoutCallback intentionally bypasses all of these checks so the owner can recover
    // messages that this validation or callback decoding would otherwise make unexecutable.
    function _validateCctpMessage(bytes calldata message) internal view returns (bytes calldata hookData) {
        MessageV2._validateMessageFormat(message);
        uint32 messageVersion = MessageV2._getVersion(message);
        if (messageVersion != SUPPORTED_MESSAGE_VERSION) {
            revert UnsupportedMessageVersion(messageVersion);
        }

        bytes calldata burnMessage = MessageV2._getMessageBody(message);
        BurnMessageV2._validateBurnMessageFormat(burnMessage);
        uint32 burnMessageVersion = BurnMessageV2._getVersion(burnMessage);
        if (burnMessageVersion != SUPPORTED_BURN_MESSAGE_VERSION) {
            revert UnsupportedBurnMessageVersion(burnMessageVersion);
        }

        address messageRecipient = _toAddress(MessageV2._getRecipient(message));
        if (messageRecipient != address(TOKEN_MESSENGER)) {
            revert InvalidMessageRecipient(messageRecipient);
        }

        bytes32 destinationCaller = MessageV2._getDestinationCaller(message);
        if (destinationCaller != _toBytes32(address(this))) {
            revert InvalidDestinationCaller(destinationCaller);
        }

        address mintRecipient = _toAddress(BurnMessageV2._getMintRecipient(burnMessage));
        if (mintRecipient != address(this)) {
            revert InvalidMintRecipient(mintRecipient);
        }

        hookData = BurnMessageV2._getHookData(burnMessage);
    }

    function _decodeCallback(bytes calldata hookData) internal view returns (CctpCallback memory callback) {
        callback = abi.decode(hookData, (CctpCallback));
        if (callback.magic != HOOK_MAGIC || callback.version != HOOK_VERSION) {
            revert InvalidCallback();
        }
        if (
            callback.refundReceiver == address(0) || callback.refundReceiver == address(USDC)
                || callback.refundReceiver == ROUTER
        ) {
            revert InvalidRefundReceiver(callback.refundReceiver);
        }
    }

    function _validateRecoveryReceiver(address receiver) internal view {
        if (
            receiver == address(0) || receiver == address(this) || receiver == address(USDC) || receiver == ROUTER
                || receiver == SHORTCUTS
        ) {
            revert InvalidRecoveryReceiver(receiver);
        }
    }

    function _mintThroughCctp(bytes calldata message, bytes calldata attestation)
        internal
        returns (uint256 mintAmount)
    {
        uint256 startingBalance = USDC.balanceOf(address(this));
        if (!MESSAGE_TRANSMITTER.receiveMessage(message, attestation)) {
            revert MessageTransmitterReturnedFalse();
        }
        mintAmount = USDC.balanceOf(address(this)) - startingBalance;
        if (mintAmount == 0) {
            revert NoTokensMinted();
        }
    }

    function _callRouter(bytes memory data) private returns (bool success) {
        address router = ROUTER;
        assembly ("memory-safe") {
            success := call(gas(), router, 0, add(data, 32), mload(data), 0, 0)
        }
    }

    function _toAddress(bytes32 value) private pure returns (address) {
        return address(uint160(uint256(value)));
    }

    function _toBytes32(address value) private pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}

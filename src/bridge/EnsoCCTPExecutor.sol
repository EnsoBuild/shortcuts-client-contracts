// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoRouter } from "../interfaces/IEnsoRouter.sol";
import { IMessageTransmitterV2 } from "../interfaces/IMessageTransmitterV2.sol";
import { ITokenMessengerV2 } from "../interfaces/ITokenMessengerV2.sol";
import { BurnMessageV2 } from "../libraries/cctp/BurnMessageV2.sol";
import { MessageV2 } from "../libraries/cctp/MessageV2.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

contract EnsoCCTPExecutor is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    bytes4 public constant HOOK_MAGIC = 0x454e534f; // a random bytes4 value
    uint8 public constant HOOK_VERSION = 1;

    IMessageTransmitterV2 public immutable MESSAGE_TRANSMITTER;
    ITokenMessengerV2 public immutable TOKEN_MESSENGER;
    IERC20 public immutable USDC;
    address public immutable ROUTER;
    address public immutable SHORTCUTS;
    uint32 public immutable SUPPORTED_MESSAGE_VERSION;
    uint32 public immutable SUPPORTED_BURN_MESSAGE_VERSION;

    struct CctpCallback {
        bytes4 magic;
        uint8 version;
        bytes32 requestId;
        address refundReceiver;
        uint256 executionFee;
        bytes callbackData;
    }

    event MessageExecuted(
        bytes32 indexed requestId, address indexed submitter, uint256 mintAmount, uint256 executionFee
    );
    event MessageRefunded(
        bytes32 indexed requestId,
        address indexed submitter,
        address refundReceiver,
        uint256 refundAmount,
        uint256 executionFee
    );

    error ExecutionFeeExceedsMintAmount(uint256 executionFee, uint256 mintAmount);
    error InvalidCallback();
    error InvalidDestinationCaller(address caller);
    error InvalidMessageRecipient(address recipient);
    error InvalidMintRecipient(address recipient);
    error InvalidMintToken(address token);
    error InvalidRecoveryReceiver(address receiver);
    error InvalidRefundReceiver(address receiver);
    error MessageTransmitterReturnedFalse();
    error NoTokensMinted();
    error NotSelf();
    error RouterCallFailed();
    error UnsupportedBurnMessageVersion(uint32 version);
    error UnsupportedMessageVersion(uint32 version);
    error ZeroAddress();

    constructor(
        address owner_,
        address messageTransmitter_,
        address tokenMessenger_,
        address usdc_,
        address router_,
        uint32 supportedMessageVersion_,
        uint32 supportedBurnMessageVersion_
    )
        Ownable(owner_)
    {
        if (
            messageTransmitter_ == address(0) || tokenMessenger_ == address(0) || usdc_ == address(0)
                || router_ == address(0)
        ) {
            revert ZeroAddress();
        }
        address shortcuts_ = IEnsoRouter(router_).shortcuts();
        if (shortcuts_ == address(0)) {
            revert ZeroAddress();
        }

        MESSAGE_TRANSMITTER = IMessageTransmitterV2(messageTransmitter_);
        TOKEN_MESSENGER = ITokenMessengerV2(tokenMessenger_);
        USDC = IERC20(usdc_);
        ROUTER = router_;
        SHORTCUTS = shortcuts_;
        SUPPORTED_MESSAGE_VERSION = supportedMessageVersion_;
        SUPPORTED_BURN_MESSAGE_VERSION = supportedBurnMessageVersion_;
    }

    function execute(bytes calldata message, bytes calldata attestation) external whenNotPaused {
        bytes calldata hookData = _validateCctpMessage(message);
        CctpCallback memory callback = _decodeCallback(hookData);
        uint256 mintAmount = _mintThroughCctp(message, attestation);

        if (callback.executionFee > mintAmount) {
            revert ExecutionFeeExceedsMintAmount(callback.executionFee, mintAmount);
        }
        uint256 callbackAmount = mintAmount - callback.executionFee;

        if (callback.executionFee != 0) {
            USDC.safeTransfer(msg.sender, callback.executionFee);
        }

        try this.executeCallback(callbackAmount, callback.callbackData) {
            emit MessageExecuted(callback.requestId, msg.sender, mintAmount, callback.executionFee);
        } catch {
            USDC.safeTransfer(callback.refundReceiver, callbackAmount);
            emit MessageRefunded(
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

        address destinationCaller = _toAddress(MessageV2._getDestinationCaller(message));
        if (destinationCaller != address(this)) {
            revert InvalidDestinationCaller(destinationCaller);
        }

        address mintRecipient = _toAddress(BurnMessageV2._getMintRecipient(burnMessage));
        if (mintRecipient != address(this)) {
            revert InvalidMintRecipient(mintRecipient);
        }

        // NOTE: unsure about this check either, could be just waste of gas.
        // removing for now.
        // uint32 sourceDomain = MessageV2._getSourceDomain(message);
        // bytes32 burnToken = BurnMessageV2._getBurnToken(burnMessage);
        // address localToken = TOKEN_MESSENGER.localMinter().getLocalToken(sourceDomain, burnToken);
        // if (localToken != address(USDC)) {
        //     revert InvalidMintToken(localToken);
        // }

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

    function _toAddress(bytes32 value) internal pure returns (address) {
        return address(uint160(uint256(value)));
    }
}

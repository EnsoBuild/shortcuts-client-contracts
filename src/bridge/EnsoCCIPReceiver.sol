// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { IEnsoCCIPReceiver } from "../interfaces/IEnsoCCIPReceiver.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { CCIPMessageDecoder } from "../libraries/CCIPMessageDecoder.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

/// @title EnsoCCIPReceiver
/// @author Enso
/// @notice Destination-side CCIP receiver that enforces replay protection, validates the delivered
///         token shape (exactly one non-zero ERC-20), decodes a payload, and either forwards funds
///         to Enso Shortcuts via the Enso Router or performs defensive refund/quarantine without reverting.
/// @dev Key properties:
///      - Relies on Chainlink CCIP Router gating via {CCIPReceiver}.
///      - Maintains idempotency with a messageId → handled flag.
///      - Validates `destTokenAmounts` has exactly one ERC-20 with non-zero amount.
///      - Decodes `(receiver, estimatedGas, shortcutData)` from the message payload (temp external helper).
///      - For environment issues (PAUSED / INSUFFICIENT_GAS), refunds to `receiver` for better UX.
///      - For malformed messages (no/too many tokens, zero amount, bad payload, zero address receiver), quarantines
///      funds in this contract.
///      - Executes Shortcuts using a self-call (`try this.execute(...)`) to catch and handle reverts.
contract EnsoCCIPReceiver is IEnsoCCIPReceiver, CCIPReceiver, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    uint256 private constant VERSION = 1;

    /// @dev Immutable Enso Router used to dispatch tokens + call Shortcuts.
    /// forge-lint: disable-next-item(screaming-snake-case-immutable)
    IEnsoRouter private immutable i_ensoRouter;

    /// @dev Replay protection: tracks CCIP message IDs that were executed/refunded/quarantined.
    /// forge-lint: disable-next-item(mixed-case-variable)
    mapping(bytes32 messageId => bool wasExecuted) private s_executedMessage;

    /// @notice Initializes the receiver with the CCIP router and Enso Router.
    /// @dev The owner is set via {Ownable} base (passed in to support 2-step ownership if desired).
    /// @param _owner Address to set as initial owner.
    /// @param _ccipRouter Address of the CCIP Router on the destination chain.
    /// @param _ensoRouter Address of the Enso Router that will execute Shortcuts.
    constructor(address _owner, address _ccipRouter, address _ensoRouter) Ownable(_owner) CCIPReceiver(_ccipRouter) {
        i_ensoRouter = IEnsoRouter(_ensoRouter);
    }

    /// @notice CCIP router callback: validate, classify (refund/quarantine/execute), and avoid reverting.
    /// @dev Flow:
    ///      1) Replay check by `messageId` (idempotent no-op if already handled).
    ///      2) Validate token shape (exactly one ERC-20, non-zero amount).
    ///      3) Decode payload `(receiver, estimatedGas, shortcutData)` using a temporary external helper.
    ///      4) Environment checks: `paused()` and `estimatedGas` hint vs `gasleft()`.
    ///      5) If non-OK → select refund policy:
    ///            - TO_RECEIVER for environment issues (PAUSED / INSUFFICIENT_GAS),
    ///            - TO_ESCROW for malformed token/payload (funds remain in this contract),
    ///            - NONE for ALREADY_EXECUTED (no-op).
    ///      6) If OK → mark executed and `try this.execute(...)`; on revert, refund to `receiver`.
    /// @param _message The CCIP Any2EVM message with metadata, payload, and delivered tokens.
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        (
            address token,
            uint256 amount,
            address receiver,
            bytes memory shortcutData,
            ErrorCode errorCode,
            bytes memory errorData
        ) = _validateMessage(_message);

        if (errorCode != ErrorCode.NO_ERROR) {
            emit MessageValidationFailed(_message.messageId, errorCode, errorData);

            RefundKind refundKind = _getRefundPolicy(errorCode);
            if (refundKind == RefundKind.NONE) {
                // ALREADY_EXECUTED → idempotent no-op (do not flip the flag again)
                return;
            }
            if (refundKind == RefundKind.TO_RECEIVER) {
                s_executedMessage[_message.messageId] = true;
                IERC20(token).safeTransfer(receiver, amount);
                return;
            }
            if (refundKind == RefundKind.TO_ESCROW) {
                s_executedMessage[_message.messageId] = true;
                // Quarantine-in-place: funds remain in this contract; ops can recover via `recoverTokens`.
                emit MessageQuarantined(_message.messageId, errorCode, token, amount, receiver);
                return;
            }

            // Should not happen; guarded to surface during development.
            revert EnsoCCIPReceiver_UnsupportedRefundKind(refundKind);
        }

        // Happy path: mark handled and attempt Shortcuts execution.
        s_executedMessage[_message.messageId] = true;

        try this.execute(token, amount, shortcutData) {
            emit ShortcutExecutionSuccessful(_message.messageId);
        } catch (bytes memory err) {
            emit ShortcutExecutionFailed(_message.messageId, err);
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function execute(address _token, uint256 _amount, bytes calldata _shortcutData) external {
        if (msg.sender != address(this)) {
            revert EnsoCCIPReceiver_OnlySelf();
        }
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(_token, _amount) });
        IERC20(_token).forceApprove(address(i_ensoRouter), _amount);
        i_ensoRouter.routeSingle(tokenIn, _shortcutData);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function recoverTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRecovered(_token, _to, _amount);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function getEnsoRouter() external view returns (address) {
        return address(i_ensoRouter);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function version() external pure returns (uint256) {
        return VERSION;
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function wasMessageExecuted(bytes32 _messageId) external view returns (bool) {
        return s_executedMessage[_messageId];
    }

    /// @dev Maps an ErrorCode to a refund policy. NONE means no action (e.g., ALREADY_EXECUTED).
    function _getRefundPolicy(ErrorCode _errorCode) private pure returns (RefundKind) {
        if (_errorCode == ErrorCode.NO_ERROR || _errorCode == ErrorCode.ALREADY_EXECUTED) {
            return RefundKind.NONE;
        }
        if (_errorCode == ErrorCode.PAUSED || _errorCode == ErrorCode.INSUFFICIENT_GAS) {
            return RefundKind.TO_RECEIVER;
        }
        // Only refund directly to the receiver when the payload decodes successfully.
        // If decoding fails (MALFORMED_MESSAGE_DATA), all fields (including `receiver`) must be treated as untrusted,
        // since a malformed payload could spoof a plausible receiver address.
        if (
            _errorCode == ErrorCode.NO_TOKENS || _errorCode == ErrorCode.TOO_MANY_TOKENS
                || _errorCode == ErrorCode.NO_TOKEN_AMOUNT || _errorCode == ErrorCode.MALFORMED_MESSAGE_DATA
                || _errorCode == ErrorCode.ZERO_ADDRESS_RECEIVER
        ) {
            return RefundKind.TO_ESCROW;
        }

        // Should not happen; guarded to surface during development.
        revert EnsoCCIPReceiver_UnsupportedErrorCode(_errorCode);
    }

    /// @dev Validates message shape and environment; does not mutate state.
    /// @return token The delivered ERC-20 token (must be non-zero if NO_ERROR).
    /// @return amount The delivered token amount (must be > 0 if NO_ERROR).
    /// @return receiver Decoded receiver from payload (valid if NO_ERROR/PAUSED/INSUFFICIENT_GAS).
    /// @return shortcutData Decoded Enso Shortcuts calldata.
    /// @return errorCode Classification of the validation result.
    /// @return errorData Optional details (see `MessageValidationFailed` doc).
    function _validateMessage(Client.Any2EVMMessage memory _message)
        private
        view
        returns (
            address token,
            uint256 amount,
            address receiver,
            bytes memory shortcutData,
            ErrorCode errorCode,
            bytes memory errorData
        )
    {
        // Replay protection
        bytes32 messageId = _message.messageId;
        if (s_executedMessage[messageId]) {
            errorData = abi.encode(messageId);
            return (token, amount, receiver, shortcutData, ErrorCode.ALREADY_EXECUTED, errorData);
        }

        // Token shape
        Client.EVMTokenAmount[] memory destTokenAmounts = _message.destTokenAmounts;
        if (destTokenAmounts.length == 0) {
            return (token, amount, receiver, shortcutData, ErrorCode.NO_TOKENS, errorData);
        }

        if (destTokenAmounts.length > 1) {
            // CCIP currently delivers at most ONE token per message. Multiple-token deliveries are not supported by the
            // protocol today, so treat any length > 1 as invalid and quarantine/refuse.
            return (token, amount, receiver, shortcutData, ErrorCode.TOO_MANY_TOKENS, errorData);
        }

        token = destTokenAmounts[0].token;
        amount = destTokenAmounts[0].amount;

        if (amount == 0) {
            return (token, amount, receiver, shortcutData, ErrorCode.NO_TOKEN_AMOUNT, errorData);
        }

        // Decode payload
        bool decodeSuccess;
        uint256 estimatedGas;
        (decodeSuccess, receiver, estimatedGas, shortcutData) = CCIPMessageDecoder.tryDecodeMessageData(_message.data);
        if (!decodeSuccess) {
            return (token, amount, receiver, shortcutData, ErrorCode.MALFORMED_MESSAGE_DATA, errorData);
        }

        // Check receiver
        if (receiver == address(0)) {
            return (token, amount, receiver, shortcutData, ErrorCode.ZERO_ADDRESS_RECEIVER, errorData);
        }

        // Environment checks (refundable to receiver)
        if (paused()) {
            return (token, amount, receiver, shortcutData, ErrorCode.PAUSED, errorData);
        }

        uint256 availableGas = gasleft();
        if (estimatedGas != 0 && availableGas < estimatedGas) {
            errorData = abi.encode(availableGas, estimatedGas);
            return (token, amount, receiver, shortcutData, ErrorCode.INSUFFICIENT_GAS, errorData);
        }

        return (token, amount, receiver, shortcutData, ErrorCode.NO_ERROR, errorData);
    }
}

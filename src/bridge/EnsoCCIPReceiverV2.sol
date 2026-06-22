// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { IEnsoCCIPReceiverV2 } from "../interfaces/IEnsoCCIPReceiverV2.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { ITypeAndVersion } from "../interfaces/ITypeAndVersion.sol";
import { CCIPMessageDecoder } from "../libraries/CCIPMessageDecoder.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

/// @title EnsoCCIPReceiverV2
/// @author Enso
/// @notice Destination-side CCIP receiver that enforces replay protection, validates the delivered
///         token shape (one or two distinct non-zero ERC-20s), decodes a payload, and either forwards
///         funds to Enso Shortcuts via the Enso Router or performs defensive refund/quarantine without
///         reverting.
/// @dev Key properties (vs. V1):
///      - Supports up to {MAX_TOKENS} (2) delivered tokens per message.
///      - Tokens/amounts come from the authoritative CCIP `destTokenAmounts` (paired, equal length);
///        the payload remains `(receiver, shortcutData)`.
///      - Relies on Chainlink CCIP Router gating via {CCIPReceiver}.
///      - Maintains idempotency with a messageId → handled flag.
///      - Validates `destTokenAmounts` has 1 or 2 non-zero, distinct ERC-20s.
///      - For environment issues (PAUSED), refunds every token to `receiver` for better UX.
///      - For malformed messages (no/too many tokens, zero amount, duplicate tokens, bad payload, zero
///        address receiver), quarantines funds in this contract.
///      - One token routes via `routeSingle`, two via `routeMulti`.
///      - Executes Shortcuts using a self-call (`try this.execute(...)`) to catch and handle reverts.
contract EnsoCCIPReceiverV2 is IEnsoCCIPReceiverV2, CCIPReceiver, Ownable2Step, Pausable, ITypeAndVersion {
    using SafeERC20 for IERC20;

    /// forge-lint: disable-next-item(screaming-snake-case-const)
    string public constant override typeAndVersion = "EnsoCCIPReceiver 2.0.0";

    /// @dev Minimum number of tokens accepted in a single CCIP message (routed via `routeSingle`).
    uint256 private constant MIN_TOKENS = 1;

    /// @dev Maximum number of distinct tokens accepted in a single CCIP message (routed via `routeMulti`).
    uint256 private constant MAX_TOKENS = 2;

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
    ///      2) Validate token shape (1 or 2 distinct ERC-20s, each non-zero amount).
    ///      3) Decode payload `(receiver, shortcutData)`.
    ///      4) Environment checks: `paused()`.
    ///      5) If non-OK → select refund policy:
    ///            - TO_RECEIVER for environment issues (PAUSED),
    ///            - TO_ESCROW for malformed token/payload (funds remain in this contract),
    ///            - NONE for ALREADY_EXECUTED (no-op).
    ///      6) If OK → mark executed and `try this.execute(...)`; on revert, refund every token to `receiver`.
    /// @param _message The CCIP Any2EVM message with metadata, payload, and delivered tokens.
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        (
            address[] memory tokens,
            uint256[] memory amounts,
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
                _refundAll(tokens, amounts, receiver);
                return;
            }
            if (refundKind == RefundKind.TO_ESCROW) {
                s_executedMessage[_message.messageId] = true;
                // Quarantine-in-place: funds remain in this contract; ops can recover via `recoverTokens`.
                emit MessageQuarantined(_message.messageId, errorCode, tokens, amounts, receiver);
                return;
            }

            // Should not happen; guarded to surface during development.
            revert EnsoCCIPReceiverV2_UnsupportedRefundKind(refundKind);
        }

        // Happy path: mark handled and attempt Shortcuts execution.
        s_executedMessage[_message.messageId] = true;

        try this.execute(tokens, amounts, shortcutData) {
            emit ShortcutExecutionSuccessful(_message.messageId);
        } catch (bytes memory err) {
            emit ShortcutExecutionFailed(_message.messageId, err);
            _refundAll(tokens, amounts, receiver);
        }
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function execute(address[] calldata _tokens, uint256[] calldata _amounts, bytes calldata _shortcutData) external {
        if (msg.sender != address(this)) {
            revert EnsoCCIPReceiverV2_OnlySelf();
        }

        uint256 length = _tokens.length;

        if (length == MIN_TOKENS) {
            Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(_tokens[0], _amounts[0]) });
            IERC20(_tokens[0]).forceApprove(address(i_ensoRouter), _amounts[0]);
            i_ensoRouter.routeSingle(tokenIn, _shortcutData);
            return;
        }

        if (length == MAX_TOKENS) {
            Token[] memory tokensIn = new Token[](length);
            for (uint256 i; i < length; ++i) {
                tokensIn[i] = Token({ tokenType: TokenType.ERC20, data: abi.encode(_tokens[i], _amounts[i]) });
                IERC20(_tokens[i]).forceApprove(address(i_ensoRouter), _amounts[i]);
            }
            i_ensoRouter.routeMulti(tokensIn, _shortcutData);
            return;
        }

        // Defensive: `_validateMessage` already gates length to [MIN_TOKENS, MAX_TOKENS], so this is
        // unreachable in normal flow. Guarded explicitly so any future caller fails closed.
        revert EnsoCCIPReceiverV2_UnsupportedTokensLength(length);
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function recoverTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRecovered(_token, _to, _amount);
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function getEnsoRouter() external view returns (address) {
        return address(i_ensoRouter);
    }

    /// @inheritdoc IEnsoCCIPReceiverV2
    function wasMessageExecuted(bytes32 _messageId) external view returns (bool) {
        return s_executedMessage[_messageId];
    }

    /// @dev Transfers every delivered token to `_to` (used for PAUSED and failed-execution refunds).
    function _refundAll(address[] memory _tokens, uint256[] memory _amounts, address _to) private {
        for (uint256 i; i < _tokens.length; ++i) {
            IERC20(_tokens[i]).safeTransfer(_to, _amounts[i]);
        }
    }

    /// @dev Maps an ErrorCode to a refund policy. NONE means no action (e.g., ALREADY_EXECUTED).
    /// @dev NO_ERROR is included for completeness; in practice this function is only called when errorCode != NO_ERROR
    /// (see _ccipReceive).
    function _getRefundPolicy(ErrorCode _errorCode) private pure returns (RefundKind) {
        if (_errorCode == ErrorCode.NO_ERROR || _errorCode == ErrorCode.ALREADY_EXECUTED) {
            return RefundKind.NONE;
        }
        if (_errorCode == ErrorCode.PAUSED) {
            return RefundKind.TO_RECEIVER;
        }
        // Only refund directly to the receiver when the payload decodes successfully.
        // If decoding fails (MALFORMED_MESSAGE_DATA), all fields (including `receiver`) must be treated as untrusted,
        // since a malformed payload could spoof a plausible receiver address.
        if (
            _errorCode == ErrorCode.NO_TOKENS || _errorCode == ErrorCode.TOO_MANY_TOKENS
                || _errorCode == ErrorCode.NO_TOKEN_AMOUNT || _errorCode == ErrorCode.DUPLICATE_TOKENS
                || _errorCode == ErrorCode.MALFORMED_MESSAGE_DATA || _errorCode == ErrorCode.ZERO_ADDRESS_RECEIVER
        ) {
            return RefundKind.TO_ESCROW;
        }

        // Should not happen; guarded to surface during development.
        revert EnsoCCIPReceiverV2_UnsupportedErrorCode(_errorCode);
    }

    /// @dev Validates message shape and environment; does not mutate state.
    /// @return tokens The delivered ERC-20 tokens (1 or 2; non-zero and distinct if NO_ERROR).
    /// @return amounts The delivered token amounts (each > 0 if NO_ERROR), aligned with `tokens`.
    /// @return receiver Decoded receiver from payload (valid if NO_ERROR/PAUSED).
    /// @return shortcutData Decoded Enso Shortcuts calldata.
    /// @return errorCode Classification of the validation result.
    /// @return errorData Optional details (see `MessageValidationFailed` doc).
    function _validateMessage(Client.Any2EVMMessage memory _message)
        private
        view
        returns (
            address[] memory tokens,
            uint256[] memory amounts,
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
            return (tokens, amounts, receiver, shortcutData, ErrorCode.ALREADY_EXECUTED, errorData);
        }

        // Token shape
        Client.EVMTokenAmount[] memory destTokenAmounts = _message.destTokenAmounts;
        uint256 tokensLength = destTokenAmounts.length;
        if (tokensLength < MIN_TOKENS) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.NO_TOKENS, errorData);
        }
        if (tokensLength > MAX_TOKENS) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.TOO_MANY_TOKENS, errorData);
        }

        // Materialize tokens/amounts from the authoritative CCIP delivery (paired, equal length).
        tokens = new address[](tokensLength);
        amounts = new uint256[](tokensLength);
        for (uint256 i; i < tokensLength; ++i) {
            tokens[i] = destTokenAmounts[i].token;
            amounts[i] = destTokenAmounts[i].amount;
            if (amounts[i] == 0) {
                errorData = abi.encode(i);
                return (tokens, amounts, receiver, shortcutData, ErrorCode.NO_TOKEN_AMOUNT, errorData);
            }
        }

        // Reject duplicate tokens in a two-token delivery (ambiguous routeMulti accounting).
        if (tokensLength == MAX_TOKENS && tokens[0] == tokens[1]) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.DUPLICATE_TOKENS, errorData);
        }

        // Decode payload
        bool decodeSuccess;
        (decodeSuccess, receiver, shortcutData) = CCIPMessageDecoder._tryDecodeMessageData(_message.data);
        if (!decodeSuccess) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.MALFORMED_MESSAGE_DATA, errorData);
        }

        // Check receiver
        if (receiver == address(0)) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.ZERO_ADDRESS_RECEIVER, errorData);
        }

        // Environment checks (refundable to receiver)
        if (paused()) {
            return (tokens, amounts, receiver, shortcutData, ErrorCode.PAUSED, errorData);
        }

        return (tokens, amounts, receiver, shortcutData, ErrorCode.NO_ERROR, errorData);
    }
}

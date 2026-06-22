// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IEnsoCCIPReceiverV2
/// @author Enso
/// @notice Interface for a CCIP destination receiver that enforces replay protection,
///         validates the delivered token shape (one or two distinct non-zero ERC-20s), decodes a
///         payload, and either forwards funds into Enso Shortcuts or performs defensive
///         refunds/quarantine.
/// @dev V2 extends V1 from a single delivered token to up to {MAX_TOKENS} tokens per message:
///      - Tokens/amounts are sourced from the authoritative CCIP `destTokenAmounts` (paired, so
///        always equal length); the payload remains `(receiver, shortcutData)`.
///      - One token routes via `EnsoRouter.routeSingle`, two via `EnsoRouter.routeMulti`.
///      - Malformed shapes never revert in `_ccipReceive`; funds are quarantined or refunded.
interface IEnsoCCIPReceiverV2 {
    /// @notice High-level validation/flow outcomes produced by `_validateMessage`.
    /// @dev Values 0–7 are intentionally identical to `EnsoCCIPReceiver` (V1) so existing decoders,
    ///      indexers and dashboards keep interpreting the same `uint8` the same way across versions.
    ///      `DUPLICATE_TOKENS` is appended (value 8) as the only V2 addition — do NOT reorder.
    /// @dev Meanings:
    /// - NO_ERROR: message is well-formed; proceed to execution.
    /// - ALREADY_EXECUTED: messageId was previously handled (idempotent no-op).
    /// - NO_TOKENS / TOO_MANY_TOKENS / NO_TOKEN_AMOUNT: token shape invalid.
    /// - MALFORMED_MESSAGE_DATA: payload (address,bytes) could not be decoded.
    /// - ZERO_ADDRESS_RECEIVER: payload receiver is the zero address.
    /// - PAUSED: contract is paused; environment block on execution.
    /// - DUPLICATE_TOKENS: a two-token delivery contained the same token twice (V2 addition).
    enum ErrorCode {
        NO_ERROR,
        ALREADY_EXECUTED,
        NO_TOKENS,
        TOO_MANY_TOKENS,
        NO_TOKEN_AMOUNT,
        MALFORMED_MESSAGE_DATA,
        ZERO_ADDRESS_RECEIVER,
        PAUSED,
        DUPLICATE_TOKENS
    }

    /// @notice Refund policy selected by the receiver for a given ErrorCode.
    /// @dev TO_RECEIVER is used for environment errors (e.g., PAUSED) after successful payload decode.
    ///      TO_ESCROW is used for malformed token/payload cases.
    enum RefundKind {
        NONE,
        TO_RECEIVER,
        TO_ESCROW
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when validation fails. See `errorCode` for the reason.
    /// @dev errorData encodings:
    ///  - ALREADY_EXECUTED: (bytes32 messageId)
    ///  - NO_TOKEN_AMOUNT: (uint256 index) of the first zero-amount token.
    ///  - Others: empty bytes unless specified by the implementation.
    event MessageValidationFailed(bytes32 indexed messageId, ErrorCode indexed errorCode, bytes errorData);

    /// @notice Funds were quarantined in the receiver instead of delivered to the payload receiver.
    /// @dev Tokens/amounts mirror the delivered CCIP `destTokenAmounts` (1 or 2 entries, paired).
    /// @param messageId The CCIP message id.
    /// @param code The validation error that triggered quarantine.
    /// @param tokens ERC-20 tokens retained.
    /// @param amounts Token amounts retained (aligned with `tokens`).
    /// @param receiver Original payload receiver (informational; may be zero if not decoded).
    event MessageQuarantined(
        bytes32 indexed messageId, ErrorCode indexed code, address[] tokens, uint256[] amounts, address receiver
    );

    /// @notice Emitted when Enso Shortcuts execution succeeds for a CCIP message.
    /// @param messageId CCIP message identifier.
    event ShortcutExecutionSuccessful(bytes32 indexed messageId);

    /// @notice Emitted when Enso Shortcuts execution reverts for a CCIP message.
    /// @param messageId CCIP message identifier.
    /// @param err ABI-encoded revert data from the failed call.
    event ShortcutExecutionFailed(bytes32 indexed messageId, bytes err);

    /// @notice Emitted when the owner recovers tokens from the receiver.
    event TokensRecovered(address indexed token, address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Revert when an external caller targets the internal executor.
    error EnsoCCIPReceiverV2_OnlySelf();

    /// @notice Revert if an unexpected ErrorCode is encountered in refund policy logic.
    error EnsoCCIPReceiverV2_UnsupportedErrorCode(ErrorCode errorCode);

    /// @notice Revert if an unexpected RefundKind is encountered in refund policy logic.
    error EnsoCCIPReceiverV2_UnsupportedRefundKind(RefundKind refundKind);

    /// @notice Revert when `execute` is reached with a token count outside [MIN_TOKENS, MAX_TOKENS].
    /// @dev Defensive guard; unreachable in normal flow since `_validateMessage` gates the length first.
    error EnsoCCIPReceiverV2_UnsupportedTokensLength(uint256 length);

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /// @notice Executes Enso Shortcuts with one or two ERC-20s previously received via CCIP.
    /// @dev MUST be callable only by the contract itself (self-call), typically from `_ccipReceive`
    ///      using `try this.execute(...)`. Implementations should guard with
    ///      `if (msg.sender != address(this)) revert EnsoCCIPReceiverV2_OnlySelf();`
    ///      Routes via `routeSingle` for one token and `routeMulti` for two.
    /// @param tokens ERC-20 tokens to route (1 or 2 entries).
    /// @param amounts Amounts of each `tokens[i]` to route (aligned with `tokens`).
    /// @param shortcutData ABI-encoded call data for the Enso Shortcuts entrypoint.
    function execute(address[] calldata tokens, uint256[] calldata amounts, bytes calldata shortcutData) external;

    /// @notice Pauses the CCIP receiver, disabling new incoming message execution until unpaused.
    /// @dev Only callable by the contract owner.
    function pause() external;

    /// @notice Provides the ability for the owner to recover any ERC-20 tokens held by this contract
    ///         (for example, after quarantine or accidental sends).
    /// @param token ERC20-token to recover.
    /// @param to Destination address to send the tokens to.
    /// @param amount The amount of tokens to send.
    function recoverTokens(address token, address to, uint256 amount) external;

    /// @notice Unpauses the CCIP receiver, re-enabling normal message processing.
    /// @dev Only callable by the contract owner.
    function unpause() external;

    /// @notice Returns the Enso Router address used by this receiver.
    /// @return router Address of the Enso Router.
    function getEnsoRouter() external view returns (address router);

    /// @notice Returns whether a CCIP message was already handled (executed/refunded/quarantined).
    /// @param messageId CCIP message identifier.
    /// @return executed True if the messageId is marked as executed/handled.
    function wasMessageExecuted(bytes32 messageId) external view returns (bool executed);
}

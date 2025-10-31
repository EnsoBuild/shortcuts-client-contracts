// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IEnsoCCIPReceiver
/// @author Enso
/// @notice Interface for a CCIP destination receiver that enforces replay protection,
///         validates delivered token shape (exactly one non-zero ERC-20), decodes a payload,
///         and either forwards funds into Enso Shortcuts or performs defensive refunds/quarantine.
/// @dev Exposes only the external/public surface of the implementing receiver:
///      - Self-call execution entry used by try/catch in `_ccipReceive`
///      - Pause/unpause and token recovery
///      - Views for router/version/replay state
interface IEnsoCCIPReceiver {
    /// @notice High-level validation/flow outcomes produced by `_validateMessage`.
    /// @dev Meanings:
    /// - NO_ERROR: message is well-formed; proceed to execution.
    /// - ALREADY_EXECUTED: messageId was previously handled (idempotent no-op).
    /// - NO_TOKENS / TOO_MANY_TOKENS / NO_TOKEN_AMOUNT: token shape invalid.
    /// - MALFORMED_MESSAGE_DATA: payload (address,uint256,bytes) could not be decoded.
    /// - ZERO_ADDRESS_RECEIVER: payload receiver is the zero address.
    /// - PAUSED: contract is paused; environment block on execution.
    /// - INSUFFICIENT_GAS: current gas < estimatedGas hint from payload.
    enum ErrorCode {
        NO_ERROR,
        ALREADY_EXECUTED,
        NO_TOKENS,
        TOO_MANY_TOKENS,
        NO_TOKEN_AMOUNT,
        MALFORMED_MESSAGE_DATA,
        ZERO_ADDRESS_RECEIVER,
        PAUSED,
        INSUFFICIENT_GAS
    }

    /// @notice Refund policy selected by the receiver for a given ErrorCode.
    /// @dev TO_RECEIVER is used for environment errors (e.g., PAUSED/INSUFFICIENT_GAS) after successful payload decode.
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
    ///  - INSUFFICIENT_GAS: (uint256 availableGas, uint256 estimatedGas)
    ///  - Others: empty bytes unless specified by the implementation.
    event MessageValidationFailed(bytes32 indexed messageId, ErrorCode errorCode, bytes errorData);

    /// @notice Funds were quarantined in the receiver instead of delivered to the payload receiver.
    /// @param messageId The CCIP message id.
    /// @param code The validation error that triggered quarantine.
    /// @param token ERC-20 token retained.
    /// @param amount Token amount retained.
    /// @param receiver Original payload receiver (informational; may be zero if not decoded).
    event MessageQuarantined(
        bytes32 indexed messageId, ErrorCode code, address token, uint256 amount, address receiver
    );

    /// @notice Emitted when Enso Shortcuts execution succeeds for a CCIP message.
    /// @param messageId CCIP message identifier.
    event ShortcutExecutionSuccessful(bytes32 indexed messageId);

    /// @notice Emitted when Enso Shortcuts execution reverts for a CCIP message.
    /// @param messageId CCIP message identifier.
    /// @param err ABI-encoded revert data from the failed call.
    event ShortcutExecutionFailed(bytes32 indexed messageId, bytes err);

    /// @notice Emitted when the owner recovers tokens from the receiver.
    event TokensRecovered(address token, address to, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Revert when an external caller targets the internal executor.
    error EnsoCCIPReceiver_OnlySelf();

    /// @notice Revert if an unexpected ErrorCode is encountered in refund policy logic.
    error EnsoCCIPReceiver_UnsupportedErrorCode(ErrorCode errorCode);

    /// @notice Revert if an unexpected RefundKind is encountered in refund policy logic.
    error EnsoCCIPReceiver_UnsupportedRefundKind(RefundKind refundKind);

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /// @notice Executes Enso Shortcuts with a single ERC-20 that was previously received via CCIP.
    /// @dev MUST be callable only by the contract itself (self-call), typically from `_ccipReceive`
    ///      using `try this.execute(...)`. Implementations should guard with
    ///      `if (msg.sender != address(this)) revert EnsoCCIPReceiver_OnlySelf();`
    /// @param token ERC-20 token to route.
    /// @param amount Amount of `token` to route.
    /// @param shortcutData ABI-encoded call data for the Enso Shortcuts entrypoint.
    function execute(address token, uint256 amount, bytes calldata shortcutData) external;

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

    /// @notice Returns a human-readable version/format indicator for off-chain tooling and tests.
    /// @return version The version number of this receiver implementation.
    function version() external view returns (uint256 version);

    /// @notice Returns whether a CCIP message was already handled (executed/refunded/quarantined).
    /// @param messageId CCIP message identifier.
    /// @return executed True if the messageId is marked as executed/handled.
    function wasMessageExecuted(bytes32 messageId) external view returns (bool executed);
}

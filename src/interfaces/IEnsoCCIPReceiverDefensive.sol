// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IEnsoCCIPReceiverDefensive
/// @author Enso
/// @notice Interface for a CCIP destination receiver that validates source (chain/sender),
///         enforces replay protection, and forwards a single bridged ERC-20 into Enso Shortcuts.
/// @dev Exposes only the external/public surface of the implementing receiver:
///      - Admin setters for allowlists
///      - Self-call execution entry used by try/catch in `_ccipReceive`
///      - Views for router/allowlists/replay state
interface IEnsoCCIPReceiverDefensive {
    enum ErrorCode {
        NO_ERROR,
        ALREADY_EXECUTED,
        NO_TOKENS,
        TOO_MANY_TOKENS,
        NO_TOKEN_AMOUNT,
        MALFORMED_MESSAGE_DATA,
        PAUSED,
        SOURCE_CHAIN_NOT_ALLOWED,
        SENDER_NOT_ALLOWED,
        INSUFFICIENT_GAS
    }

    enum RefundKind {
        NONE,
        TO_RECEIVER,
        TO_ESCROW
    }

    struct Escrow {
        address token; // ERC20 token being held
        uint256 amount; // amount held
        address receiver; // payload receiver for reference; may be 0
        bool isEscrow; // presence flag
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an allowed sender is (de)authorized for a source chain.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param sender Address of the source application on that chain.
    /// @param isAllowed True if allowed, false if disallowed.
    event AllowedSenderSet(uint64 indexed sourceChainSelector, address indexed sender, bool isAllowed);

    /// @notice Emitted when a source chain is (de)authorized.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param isAllowed True if allowed, false if disallowed.
    event AllowedSourceChainSet(uint64 indexed sourceChainSelector, bool isAllowed);

    /// @notice Emitted when validation fails. See `errorCode` for class.
    /// @dev errorData encodings:
    ///  - ALREADY_EXECUTED: (bytes32 messageId)
    ///  - SOURCE_CHAIN_NOT_ALLOWED: (uint64 sourceChainSelector)
    ///  - SENDER_NOT_ALLOWED: (uint64 sourceChainSelector, address sender)
    ///  - INSUFFICIENT_GAS: (uint256 availableGas, uint256 estimatedGas)
    ///  - Others: empty bytes unless specified.
    event MessageValidationFailed(bytes32 indexed messageId, ErrorCode errorCode, bytes errorData);

    /// @notice Emitted when Enso Shortcuts execution succeeds for a CCIP message.
    /// @param messageId CCIP message identifier.
    event ShortcutExecutionSuccessful(bytes32 indexed messageId);

    /// @notice Emitted when Enso Shortcuts execution reverts for a CCIP message.
    /// @param messageId CCIP message identifier.
    /// @param err ABI-encoded revert data from the failed call.
    event ShortcutExecutionFailed(bytes32 indexed messageId, bytes err);

    /// @notice Funds were quarantined to escrow instead of delivered to the payload receiver.
    /// @param messageId The CCIP message id.
    /// @param code The validation error that triggered quarantine.
    /// @param token ERC-20 token moved to escrow.
    /// @param amount Token amount quarantined.
    /// @param receiver Original payload receiver (informational; may be zero if not decoded).
    event MessageQuarantined(
        bytes32 indexed messageId, ErrorCode code, address token, uint256 amount, address receiver
    );
    event EscrowSwept(bytes32 indexed messageId, address token, uint256 amount, address to);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Revert when an external caller targets the internal executor.
    error EnsoCCIPReceiver_OnlySelf();
    error EnsoCCIPReceiver_MissingEscrow(bytes32 messageId);
    error EnsoCCIPReceiver_UnsupportedErrorCode(ErrorCode errorCode);
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

    /// @notice Pauses the CCIP receiver, disabling new incoming messages until unpaused.
    /// @dev Only callable by the contract owner. While paused, `_ccipReceive` should
    ///      revert or ignore messages to prevent execution.
    function pause() external;

    /// @notice Adds or removes an allowed sender for a specific source chain.
    /// @dev Typically `onlyOwner`. Idempotent (setting an already-set value is allowed).
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param sender Address of the source application on that chain.
    /// @param isAllowed True to allow, false to disallow.
    function setAllowedSender(uint64 sourceChainSelector, address sender, bool isAllowed) external;

    /// @notice Adds or removes an allowed source chain.
    /// @dev Typically `onlyOwner`. Idempotent (setting an already-set value is allowed).
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param isAllowed True to allow, false to disallow.
    function setAllowedSourceChain(uint64 sourceChainSelector, bool isAllowed) external;

    function sweepMessageInEscrow(bytes32 messageId, address token, uint256 amount, address to) external;

    /// @notice Unpauses the CCIP receiver, re-enabling message processing.
    /// @dev Only callable by the contract owner. Resumes normal operation after a pause.
    function unpause() external;

    /// @notice Returns the Enso Router address used by this receiver.
    /// @return router Address of the Enso Router.
    function getEnsoRouter() external view returns (address router);

    function isMessageInEscrow(bytes32 messageId) external view returns (bool);

    /// @notice Returns whether a sender is allowlisted for a given source chain.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param sender Address of the source application on that chain.
    /// @return allowed True if the sender is allowed.
    function isSenderAllowed(uint64 sourceChainSelector, address sender) external view returns (bool allowed);

    /// @notice Returns whether a source chain is allowlisted.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @return allowed True if the source chain is allowed.
    function isSourceChainAllowed(uint64 sourceChainSelector) external view returns (bool allowed);

    function version() external returns (uint256 version);

    /// @notice Returns whether a CCIP message was already executed.
    /// @param messageId CCIP message identifier.
    /// @return executed True if the message was marked as executed.
    function wasMessageExecuted(bytes32 messageId) external view returns (bool executed);
}

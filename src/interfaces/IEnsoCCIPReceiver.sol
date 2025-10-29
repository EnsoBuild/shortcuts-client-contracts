// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IEnsoCCIPReceiver
/// @author Enso
/// @notice Interface for a CCIP destination receiver that validates source (chain/sender),
///         enforces replay protection, and forwards a single bridged ERC-20 into Enso Shortcuts.
/// @dev Exposes only the external/public surface of the implementing receiver:
///      - Admin setters for allowlists
///      - Self-call execution entry used by try/catch in `_ccipReceive`
///      - Views for router/allowlists/replay state
interface IEnsoCCIPReceiver {
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

    /// @notice Emitted when Enso Shortcuts execution succeeds for a CCIP message.
    /// @param messageId CCIP message identifier.
    event ShortcutExecutionSuccessful(bytes32 indexed messageId);

    /// @notice Emitted when Enso Shortcuts execution reverts for a CCIP message.
    /// @param messageId CCIP message identifier.
    /// @param err ABI-encoded revert data from the failed call.
    event ShortcutExecutionFailed(bytes32 indexed messageId, bytes err);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Revert when a CCIP message with the same ID was already processed.
    /// @param messageId CCIP message identifier.
    error EnsoCCIPReceiver_AlreadyExecuted(bytes32 messageId);

    /// @notice Revert when available gas is below the estimated threshold from payload.
    /// @param availableGas Remaining gas at the check point.
    /// @param estimatedGas Gas amount the sender expects to be available.
    error EnsoCCIPReceiver_InsufficientGas(uint256 availableGas, uint256 estimatedGas);

    /// @notice Revert when the CCIP message carries no tokens.
    error EnsoCCIPReceiver_NoTokens();

    /// @notice Revert when the delivered single token amount is zero.
    /// @param token ERC-20 token address.
    error EnsoCCIPReceiver_NoTokenAmount(address token);

    /// @notice Revert when an external caller targets the internal executor.
    error EnsoCCIPReceiver_OnlySelf();

    /// @notice Revert when the source chain is not allowlisted.
    /// @param sourceChainSelector Chain selector of the source network.
    error EnsoCCIPReceiver_SourceChainNotAllowed(uint64 sourceChainSelector);

    /// @notice Revert when the source sender is not allowlisted for a given chain.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param sender Address of the source application.
    error EnsoCCIPReceiver_SenderNotAllowed(uint64 sourceChainSelector, address sender);

    /// @notice Revert when more than one token is delivered (not supported).
    error EnsoCCIPReceiver_TooManyTokens();

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

    /// @notice Unpauses the CCIP receiver, re-enabling message processing.
    /// @dev Only callable by the contract owner. Resumes normal operation after a pause.
    function unpause() external;

    /// @notice Returns the Enso Router address used by this receiver.
    /// @return router Address of the Enso Router.
    function getEnsoRouter() external view returns (address router);

    /// @notice Returns whether a sender is allowlisted for a given source chain.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @param sender Address of the source application on that chain.
    /// @return allowed True if the sender is allowed.
    function isSenderAllowed(uint64 sourceChainSelector, address sender) external view returns (bool allowed);

    /// @notice Returns whether a source chain is allowlisted.
    /// @param sourceChainSelector Chain selector of the source network.
    /// @return allowed True if the source chain is allowed.
    function isSourceChainAllowed(uint64 sourceChainSelector) external view returns (bool allowed);

    /// @notice Returns whether a CCIP message was already executed.
    /// @param messageId CCIP message identifier.
    /// @return executed True if the message was marked as executed.
    function wasMessageExecuted(bytes32 messageId) external view returns (bool executed);
}

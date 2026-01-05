// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

/// @title IEnsoWalletV2
/// @author Enso
/// @notice Interface for Enso Wallet V2 - a minimal wallet that supports shortcuts and multi-send operations
interface IEnsoWalletV2 {
    /// @notice Thrown when an execution call fails without revert reason
    error EnsoWalletV2_ExecutionFailedNoReason();

    /// @notice Thrown when the sender is not authorized
    /// @param sender The address that attempted the unauthorized call
    error EnsoWalletV2_InvalidSender(address sender);

    /// @notice Emitted when an executor is added or removed
    /// @param executor The address of the executor
    /// @param allowed Whether the executor is allowed to call executeShortcut and multiSend
    event ExecutorSet(address indexed executor, bool allowed);

    /// @notice The version of the wallet contract
    function VERSION() external view returns (string memory);

    /// @notice Returns whether an address is authorized to call executeShortcut and multiSend
    /// @param executor The address to check
    /// @return isAllowed Whether the address is authorized
    function executors(address executor) external view returns (bool isAllowed);

    /// @notice Authorizes or deauthorizes an address to call executeShortcut and multiSend
    /// @param executor The address to authorize or deauthorize
    /// @param allowed Whether the address should be allowed
    function setExecutor(address executor, bool allowed) external;

    /// @notice Initializes the wallet with an owner address
    /// @param owner_ The address that will own this wallet
    function initialize(address owner_) external;

    /// @notice Executes an arbitrary call to a target contract
    /// @param target The address of the contract to call
    /// @param value The amount of native token to send with the call
    /// @param data The calldata to send to the target contract
    /// @return success Whether the call succeeded
    function execute(address target, uint256 value, bytes memory data) external payable returns (bool success);

    /// @notice Executes a shortcut on EnsoWalletV2
    /// @param accountId The account identifier
    /// @param requestId The request identifier
    /// @param commands The commands to execute
    /// @param state The state data for execution
    /// @return response The response from the shortcut execution
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        external
        payable
        returns (bytes[] memory response);
}


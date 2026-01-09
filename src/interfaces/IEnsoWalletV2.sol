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

    /// @notice The version of the wallet contract
    function VERSION() external view returns (string memory);

    /// @notice Initializes the wallet with an owner address
    /// @param owner_ The address that will own this wallet
    function initialize(address owner_) external;

    /// @notice Executes an arbitrary call to a target contract
    /// @param target The address of the contract to call
    /// @param value The amount of native token to send with the call
    /// @param data The calldata to send to the target contract
    /// @return success Whether the call succeeded
    function execute(address target, uint256 value, bytes memory data) external payable returns (bool success);
}


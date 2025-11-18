// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Token, TokenType } from "../../interfaces/IEnsoRouter.sol";

/// @title IEnsoWalletV2Factory
/// @author Enso
/// @notice Interface for factory that deploys deterministic Enso Wallet V2 instances
interface IEnsoWalletV2Factory {
    /// @notice Emitted when a new wallet is deployed
    /// @param wallet The address of the deployed wallet
    /// @param account The account address that owns the wallet
    event EnsoWalletV2Deployed(address wallet, address indexed account);

    /// @notice Thrown when an execution call fails
    error EnsoWalletV2Factory_ExecutionFailed();

    /// @notice Thrown when an unsupported token type is provided
    /// @param tokenType The unsupported token type
    error EnsoWalletV2Factory_UnsupportedTokenType(TokenType tokenType);

    /// @notice Thrown when msg.value doesn't match the expected amount
    /// @param value The actual msg.value sent
    /// @param expectedAmount The expected amount
    error EnsoWalletV2Factory_WrongMsgValue(uint256 value, uint256 expectedAmount);

    /// @notice Returns the implementation contract address used for cloning
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Deploys a wallet for the given account (idempotent)
    /// @param account The account address that will own the wallet
    /// @return wallet The deployed wallet address
    function deploy(address account) external returns (address wallet);

    /// @notice Deploys a wallet, transfers token, and executes calldata in one transaction
    /// @param tokenIn The token to transfer to the wallet
    /// @param data The calldata to execute on the wallet
    /// @return wallet The deployed wallet address
    /// @return response The return data from the execution
    function deployAndExecute(
        Token calldata tokenIn,
        bytes calldata data
    )
        external
        payable
        returns (address wallet, bytes memory response);

    /// @notice Returns the deterministic address for a given account
    /// @param account The account address
    /// @return The wallet address that would be deployed for this account
    function getAddress(address account) external view returns (address);
}


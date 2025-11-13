// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title ITypeAndVersion
/// @author Enso
/// @notice Provides a human-readable identifier for the contract type and its version.
interface ITypeAndVersion {
    /// @return A string containing the contract type and semantic version.
    function typeAndVersion() external pure returns (string memory);
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IIntentOracle {
    /// @notice Price of `base` in `quote`: WAD-scaled quote base units per base unit.
    /// @return value The price
    /// @return asOf Timestamp of the evidence behind it, checked against the source's staleness
    function read(
        bytes32 intent,
        address base,
        address quote,
        bytes calldata proof
    )
        external
        view
        returns (uint256 value, uint64 asOf);
}

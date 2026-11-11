// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// Circle CCTP V2 TokenMessenger, the entry point BridgeGuardian uses.
interface ITokenMessengerV2 {
    /// @param maxFee The most the destination may deduct from `amount` as the transfer fee
    /// @param minFinalityThreshold 1000 = fast, 2000 = standard (finalized)
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    )
        external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice Helper contract to encode Orderly deposit params
 */
contract OrderlyHelpers {
    function getOrderlyOmniChainDepositParams(
        bytes32 brokerHash,
        address receiver
    )
        external
        pure
        returns (bytes32 accountId)
    {
        return keccak256(abi.encode(receiver, brokerHash));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice Helper contract to encode Orderly One deposit params
 */
contract OrderlyOneHelpers {
    function getOrderlyOneAccountId(bytes32 brokerHash, address receiver) external pure returns (bytes32 accountId) {
        return keccak256(abi.encode(receiver, brokerHash));
    }
}

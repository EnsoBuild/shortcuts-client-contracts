// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

interface IEnsoWalletV2 {
    error ExecutionFailed();
    error InvalidSender(address sender);

    function initialize(address owner_) external;

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


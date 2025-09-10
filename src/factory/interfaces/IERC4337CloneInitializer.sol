// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC4337CloneInitializer {
    function initialize(address account, address signer, address entryPoint) external;
    function initializeAndExecuteShortcut(
        address account,
        address signer,
        address entryPoint,
        bytes calldata data
    )
        external
        payable;
}

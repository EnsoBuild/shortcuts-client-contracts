// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract IntentEmitter {
    function emitIntent(bytes32 requestId, address executor, bytes calldata ciphertext) external {
        emit PublishIntent(requestId, executor, ciphertext);
    }

    event PublishIntent(bytes32 indexed requestId, address indexed executor, bytes ciphertext);
}

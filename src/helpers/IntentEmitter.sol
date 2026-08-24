// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Intent } from "../wallet/EphemeralIntentExecutor.sol";

contract IntentEmitter {
    function emitIntent(
        bytes32 requestId,
        address executor,
        Intent intent,
        RequestMetadata metadata,
        bytes calldata signature
    )
        external
    {
        emit PublishIntent(requestId, executor, intent, metadata, signature);
    }

    event PublishIntent(
        bytes32 indexed requestId, address indexed executor, Intent intent, RequestMetadata metadata, bytes signature
    );
}

struct RequestMetadata {
    uint256 fee;
    address feeReceiver;
    string[] ignoreAggregators;
    string[] ignoreStandards;
}

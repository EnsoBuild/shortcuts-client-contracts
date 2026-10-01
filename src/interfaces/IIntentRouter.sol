// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Intent } from "./IIntent.sol";

interface IIntentRouter {
    function executeIntent(
        Intent calldata intent,
        bytes calldata signature,
        bytes calldata route
    )
        external
        returns (bytes memory response);

    function cancel(uint256 nonce) external;

    function hash(Intent calldata intent) external view returns (bytes32);
}

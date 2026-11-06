// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Intent } from "./IIntent.sol";

interface IIntentRouter {
    event IntentExecuted(address indexed owner, uint256 indexed nonce, bytes32 intentHash);
    event IntentCancelled(address indexed owner, uint256 indexed nonce);

    /// @param router Used only when the intent's constraints name no router
    /// @param routes Keeper bytes per rule, used only by rules without a committed route
    /// @param contexts Guardian context per handoff
    function executeIntent(
        Intent calldata intent,
        bytes calldata signature,
        address router,
        bytes[] calldata routes,
        bytes[] calldata contexts
    )
        external
        payable;

    function cancel(uint256[] calldata nonces) external;

    function hash(Intent calldata intent) external view returns (bytes32);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IntentRouter } from "../src/router/IntentRouter.sol";
import { Script } from "forge-std/Script.sol";

/// Salted CREATE2. Routes run through the router each intent names, so the IntentRouter deploys no
/// EnsoShortcuts of its own. Links IntentHash and IntentEvaluator; see EphemeralDeployer.
contract IntentRouterDeployer is Script {
    function run() public returns (IntentRouter router) {
        vm.startBroadcast();
        router = new IntentRouter{ salt: "IntentRouter" }();
        vm.stopBroadcast();
    }
}

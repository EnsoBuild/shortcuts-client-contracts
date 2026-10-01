// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../src/EnsoShortcuts.sol";
import { IntentRouter } from "../src/router/IntentRouter.sol";
import { Script } from "forge-std/Script.sol";

contract IntentRouterDeployer is Script {
    function run() public returns (IntentRouter router, EnsoShortcuts shortcuts) {
        vm.startBroadcast();
        router = new IntentRouter{ salt: "IntentRouter" }();
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IntentEmitter } from "../src/helpers/IntentEmitter.sol";
import { Script } from "forge-std/Script.sol";

contract IntentEmitterDeployer is Script {
    function run() public returns (IntentEmitter emitter) {
        vm.startBroadcast();

        emitter = new IntentEmitter{ salt: "IntentEmitter" }();

        vm.stopBroadcast();
    }
}

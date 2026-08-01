// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DeepstateSwapHelpers } from "../src/helpers/DeepstateSwapHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract DeepstateSwapHelpersDeployer is Script {
    function run() public returns (DeepstateSwapHelpers deepstateSwapHelpers) {
        vm.startBroadcast();

        deepstateSwapHelpers = new DeepstateSwapHelpers{ salt: "DeepstateSwapHelpers" }();

        vm.stopBroadcast();
    }
}

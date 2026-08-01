// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DeepstateSwapHelpers } from "../src/helpers/DeepstateSwapHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract DeepstateSwapHelpersDeployer is Script {
    function run() public returns (DeepstateSwapHelpers deepstateSwapHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        deepstateSwapHelpers = new DeepstateSwapHelpers{ salt: "DeepstateSwapHelpers" }();

        vm.stopBroadcast();
    }
}

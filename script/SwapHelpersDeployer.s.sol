// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SwapHelpers } from "../src/helpers/SwapHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract SwapHelpersDeployer is Script {
    function run() public returns (SwapHelpers swapHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        swapHelpers = new SwapHelpers{ salt: "SwapHelpers" }();

        vm.stopBroadcast();
    }
}

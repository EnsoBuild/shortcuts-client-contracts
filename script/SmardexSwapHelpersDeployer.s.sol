// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SmardexSwapHelpers } from "../src/helpers/SmardexSwapHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract SmardexSwapHelpersDeployer is Script {
    function run() public returns (SmardexSwapHelpers smardexSwapHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Stateless pure encoder: router-agnostic, same address (CREATE2) on every chain.
        smardexSwapHelpers = new SmardexSwapHelpers{ salt: "SmardexSwapHelpers" }();

        vm.stopBroadcast();
    }
}

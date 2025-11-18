// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { HyperCoreHelpers } from "../src/helpers/HyperCoreHelpers.sol";
import "forge-std/Script.sol";

contract HyperCoreHelpersDeployer is Script {
    function run() public returns (HyperCoreHelpers hyperCoreHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // NOTE: replace version in `salt`
        hyperCoreHelpers = new HyperCoreHelpers{ salt: "HyperCoreHelpers_v1" }();

        vm.stopBroadcast();
    }
}

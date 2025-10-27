// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { HyperCoreHelpers } from "../src/helpers/HyperCoreHelpers.sol";
import "forge-std/Script.sol";

contract HyperCoreHelpersDeployer is Script {
    function run() public returns (HyperCoreHelpers hyperCoreHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory version = "1"; // NOTE: replace version in `salt`
        vm.startBroadcast(deployerPrivateKey);

        hyperCoreHelpers = new HyperCoreHelpers{ salt: "HyperCoreHelpers_v1" }();

        vm.stopBroadcast();
    }
}

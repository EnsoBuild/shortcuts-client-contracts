// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EIP7702EnsoShortcuts } from "../src/delegate/EIP7702EnsoShortcuts.sol";
import { Script } from "forge-std/Script.sol";

struct EIP7702EnsoShortcutsDeployerResult {
    EIP7702EnsoShortcuts shortcuts;
}

contract EIP7702EnsoShortcutsDeployer is Script {
    function run() public returns (EIP7702EnsoShortcutsDeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.shortcuts = new EIP7702EnsoShortcuts{ salt: "EIP7702EnsoShortcuts" }();

        vm.stopBroadcast();
    }
}

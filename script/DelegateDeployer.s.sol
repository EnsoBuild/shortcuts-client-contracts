// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { DelegateEnsoShortcuts } from "../src/delegate/DelegateEnsoShortcuts.sol";
import { Script } from "forge-std/Script.sol";

struct DelegateDeployerResult {
    DelegateEnsoShortcuts delegate;
}

contract DelegateDeployer is Script {
    function run() public returns (DelegateDeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.delegate = new DelegateEnsoShortcuts{ salt: "DelegateEnsoShortcuts" }();

        vm.stopBroadcast();
    }
}

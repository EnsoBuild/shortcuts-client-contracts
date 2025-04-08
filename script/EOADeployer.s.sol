// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/delegate/EOAEnsoShortcuts.sol";
import "forge-std/Script.sol";

struct EOADeployerResult {
    EOAEnsoShortcuts shortcuts;
}

contract EOADeployer is Script {
    function run() public returns (EOADeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.shortcuts = new EOAEnsoShortcuts{ salt: "EOAEnsoShortcuts" }();

        vm.stopBroadcast();
    }
}

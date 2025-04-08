// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/delegate/EIP7702EnsoShortcuts.sol";
import "forge-std/Script.sol";

struct EOADeployerResult {
    EIP7702EnsoShortcuts shortcuts;
}

contract EOADeployer is Script {
    function run() public returns (EOADeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.shortcuts = new EIP7702EnsoShortcuts{ salt: "EIP7702EnsoShortcuts" }();

        vm.stopBroadcast();
    }
}

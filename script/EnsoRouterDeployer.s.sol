// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/EnsoShortcuts.sol";
import "../src/router/EnsoRouter.sol";
import "forge-std/Script.sol";

struct DeployerResult {
    EnsoRouter router;
    EnsoShortcuts shortcuts;
}

contract Deployer is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.router = new EnsoRouter{ salt: "EnsoRouter" }();
        result.shortcuts = EnsoShortcuts(payable(result.router.shortcuts()));

        vm.stopBroadcast();
    }
}

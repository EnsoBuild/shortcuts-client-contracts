// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import "../src/flashloan/EnsoFlashloanShortcuts.sol";
import "forge-std/Script.sol";

contract FlashloanDeployer is Script {
    function run() public returns (EnsoFlashloanShortcuts flashloanShortcuts) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        flashloanShortcuts = new EnsoFlashloanShortcuts{ salt: "EnsoFlashloanShortcuts" }();

        vm.stopBroadcast();
    }
}

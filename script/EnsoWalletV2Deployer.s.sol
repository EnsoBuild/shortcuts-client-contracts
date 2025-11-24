// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/wallet/EnsoWalletV2.sol";
import "../src/factory/EnsoWalletV2Factory.sol";
import "forge-std/Script.sol";

contract EnsoWalletV2Deployer is Script {
    function run() public returns (EnsoWalletV2 implementation, EnsoWalletV2Factory factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        implementation = new EnsoWalletV2{ salt: "EnsoWalletV2" }();
        factory = new EnsoWalletV2Factory{ salt: "EnsoWalletV2Factory" }(address(implementation));

        vm.stopBroadcast();
    }
}

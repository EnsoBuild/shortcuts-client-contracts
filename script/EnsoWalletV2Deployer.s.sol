// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoWalletV2Factory } from "../src/factory/EnsoWalletV2Factory.sol";
import { EnsoWalletV2 } from "../src/wallet/EnsoWalletV2.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoWalletV2Deployer is Script {
    function run() public returns (EnsoWalletV2 implementation, EnsoWalletV2Factory factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        implementation = new EnsoWalletV2{ salt: "EnsoWalletV2" }();
        //implementation = EnsoWalletV2(payable(0xA04df79c7e91f393B64e7BfECbfFA13A9f9F2829));
        factory = new EnsoWalletV2Factory{ salt: "EnsoWalletV2Factory" }(address(implementation));

        vm.stopBroadcast();
    }
}

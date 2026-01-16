// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BalancerHelpers } from "../src/helpers/BalancerHelpers.sol";
import "forge-std/Script.sol";

contract BalancerHelpersDeployer is Script {
    function run() public returns (BalancerHelpers balancerHelpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        balancerHelpers = new BalancerHelpers{ salt: "BalancerHelpers" }();

        vm.stopBroadcast();
    }
}

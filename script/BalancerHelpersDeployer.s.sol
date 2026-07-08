// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BalancerHelpers } from "../src/helpers/BalancerHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract BalancerHelpersDeployer is Script {
    function run() public returns (BalancerHelpers balancerHelpers) {

        vm.startBroadcast();

        balancerHelpers = new BalancerHelpers{ salt: "BalancerHelpers" }();

        vm.stopBroadcast();
    }
}

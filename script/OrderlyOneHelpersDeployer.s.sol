// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { OrderlyOneHelpers } from "../src/helpers/OrderlyOneHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract OrderlyOneHelpersDeployer is Script {
    function run() public returns (OrderlyOneHelpers orderlyOneHelpers) {

        vm.startBroadcast();
        orderlyOneHelpers = new OrderlyOneHelpers{ salt: "OrderlyOneHelpers" }();
        vm.stopBroadcast();
    }
}

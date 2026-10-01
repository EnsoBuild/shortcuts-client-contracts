// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DecimalHelpers } from "../src/helpers/DecimalHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract DecimalHelpersDeployer is Script {
    function run() public returns (DecimalHelpers decimalHelpers) {
        vm.startBroadcast();

        decimalHelpers = new DecimalHelpers{ salt: "DecimalHelpers" }();

        vm.stopBroadcast();
    }
}

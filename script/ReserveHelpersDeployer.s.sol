// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ReserveHelpers } from "../src/helpers/ReserveHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract ReserveHelpersDeployer is Script {
    function run() public returns (ReserveHelpers reserveHelpers) {

        vm.startBroadcast();

        reserveHelpers = new ReserveHelpers{ salt: "ReserveHelpers" }();

        vm.stopBroadcast();
    }
}

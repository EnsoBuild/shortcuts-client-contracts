// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { MaverickV2Helpers } from "../src/helpers/MaverickV2Helpers.sol";
import { Script } from "forge-std/Script.sol";

contract SwapHelpersDeployer is Script {
    function run() public returns (MaverickV2Helpers maverickV2Helpers) {

        vm.startBroadcast();

        maverickV2Helpers = new MaverickV2Helpers{ salt: "MaverickV2Helpers" }();

        vm.stopBroadcast();
    }
}

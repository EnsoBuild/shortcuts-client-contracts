// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TransferHelpers } from "../src/helpers/TransferHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract TransferHelpersDeployer is Script {
    function run() public returns (TransferHelpers transferHelpers) {
        vm.startBroadcast();

        transferHelpers = new TransferHelpers{ salt: "TransferHelpers" }();

        vm.stopBroadcast();
    }
}

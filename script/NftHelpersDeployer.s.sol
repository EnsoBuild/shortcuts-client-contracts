// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { NftHelpers } from "../src/helpers/NftHelpers.sol";
import { Script } from "forge-std/Script.sol";

contract NftHelpersDeployer is Script {
    function run() public returns (NftHelpers nftHelpers) {
        vm.startBroadcast();

        nftHelpers = new NftHelpers{ salt: "NftHelpers" }();

        vm.stopBroadcast();
    }
}

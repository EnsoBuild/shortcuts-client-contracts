// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ERC20Helpers } from "../src/helpers/ERC20Helpers.sol";
import { Script } from "forge-std/Script.sol";

contract ERC20HelpersDeployer is Script {
    function run() public returns (ERC20Helpers erc20Helpers) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        erc20Helpers = new ERC20Helpers{ salt: "ERC20Helpers" }();

        vm.stopBroadcast();
    }
}

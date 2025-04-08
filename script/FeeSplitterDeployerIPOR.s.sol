// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

struct DeployerResult {
    FeeSplitter feeSplitter;
}

// Deployer for the IPOR FeeSplitter
contract DeployerFeeSplitter is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address enso = 0x2C0b46F1276A93B458346e53f6B7B57Aba20D7D1;
        address ipor = 0xB7bE82790d40258Fd028BEeF2f2007DC044F3459;

        address[] memory recipients = new address[](2);
        recipients[0] = ipor;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        result.feeSplitter = new FeeSplitter(enso, recipients, shares);
    }
}

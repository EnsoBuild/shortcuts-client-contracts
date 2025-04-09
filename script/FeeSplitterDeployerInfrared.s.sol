// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

struct DeployerResult {
    FeeSplitter feeSplitter;
}

// Deployer for the Infrared FeeSplitter
contract DeployerFeeSpliter is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address enso = 0xA67B61399B8b817e763f05dEF4694F22f1bDCC7d;
        address infrared = 0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0;

        address[] memory recipients = new address[](2);
        recipients[0] = infrared;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        result.feeSplitter = new FeeSplitter(enso, recipients, shares);
    }
}

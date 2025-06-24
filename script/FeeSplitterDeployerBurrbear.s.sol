// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

// Deployer for the Infrared FeeSplitter
contract FeeSplitterDeployerBurrbear is Script {
    function run() public returns (address feeSplitter, address enso, address burrbear) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        enso = 0xA67B61399B8b817e763f05dEF4694F22f1bDCC7d;
        burrbear = 0xD285fa1650F575772c31c8647Fe76ff27F356844;

        address[] memory recipients = new address[](2);
        recipients[0] = burrbear;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        feeSplitter = address(new FeeSplitter(enso, recipients, shares));
    }
}

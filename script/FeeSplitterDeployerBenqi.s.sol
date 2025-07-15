// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

struct DeployerResult {
    FeeSplitter feeSplitter;
}

// Deployer for the Benqi FeeSplitter
contract DeployerFeeSpliter is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address enso = 0x69AFa05352B3797b8D08cE3B5EDf27eb0585D560;
        address benqi = 0x21edC6993fE6F2b2610955b5F81820DFa57711EB;

        address[] memory recipients = new address[](2);
        recipients[0] = benqi;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        result.feeSplitter = new FeeSplitter(enso, recipients, shares);
    }
}

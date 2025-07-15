// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

// Deployer for the Origami FeeSplitter
contract FeeSplitterDeployerOrigami is Script {
    mapping(uint256 => address) private ensoAddresses;
    mapping(uint256 => address) private origamiAddresses;

    constructor() {
        ensoAddresses[1] = 0xAb27dB9E0105AF3d9717b0CcEf11e2CC65515609; //ethereum
        ensoAddresses[80_094] = 0xA67B61399B8b817e763f05dEF4694F22f1bDCC7d; //bera

        origamiAddresses[1] = 0x781B4c57100738095222bd92D37B07ed034AB696; //ethereum
        origamiAddresses[80_094] = 0x781B4c57100738095222bd92D37B07ed034AB696; //bera
    }

    function run() public returns (address feeSplitter, address enso, address origami) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;

        enso = ensoAddresses[chainId];
        origami = origamiAddresses[chainId];
        if (enso == address(0)) revert();
        if (origami == address(0)) revert();

        address[] memory recipients = new address[](2);
        recipients[0] = origami;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        feeSplitter = address(new FeeSplitter(enso, recipients, shares));
    }
}

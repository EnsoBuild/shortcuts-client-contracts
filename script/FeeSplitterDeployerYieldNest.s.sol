// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

// Deployer for the Infrared FeeSplitter
contract FeeSplitterDeployerYieldNest is Script {
    mapping(uint256 => address) private ensoAddresses;
    mapping(uint256 => address) private yieldAddresses;

    constructor() {
        ensoAddresses[1] = 0xAb27dB9E0105AF3d9717b0CcEf11e2CC65515609; //ethereum
        ensoAddresses[56] = 0xA9Fee8f645224c1fE41d6206e28De2742320789f; //binance
        ensoAddresses[8453] = 0x69AFa05352B3797b8D08cE3B5EDf27eb0585D560; //base

        yieldAddresses[1] = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183; //ethereum
        yieldAddresses[56] = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183; //binance
        yieldAddresses[8453] = 0xC92Dd1837EBcb0365eB0a8795f9c8E474f8B6183; //base
    }

    function run() public returns (address feeSplitter, address enso, address yieldNest) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;

        enso = ensoAddresses[chainId];
        yieldNest = yieldAddresses[chainId];
        if (enso == address(0)) revert();
        if (yieldNest == address(0)) revert();

        address[] memory recipients = new address[](2);
        recipients[0] = yieldNest;
        recipients[1] = enso;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        feeSplitter = address(new FeeSplitter(enso, recipients, shares));
    }
}

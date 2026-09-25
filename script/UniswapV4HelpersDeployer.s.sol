// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniswapV4Helpers } from "../src/helpers/UniswapV4Helpers.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

contract UniswapV4HelpersDeployer is Script {
    function run() public returns (UniswapV4Helpers uniswapV4Helpers, address poolManager) {
        vm.startBroadcast();

        uint256 chainId = block.chainid;

        if (chainId == ChainId.ETHEREUM) {
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else if (chainId == ChainId.OPTIMISM) {
            poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
        } else if (chainId == ChainId.BINANCE) {
            poolManager = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
        } else if (chainId == ChainId.UNICHAIN) {
            poolManager = 0x1F98400000000000000000000000000000000004;
        } else if (chainId == ChainId.POLYGON) {
            poolManager = 0x67366782805870060151383F4BbFF9daB53e5cD6;
        } else if (chainId == ChainId.MONAD) {
            poolManager = 0x188d586Ddcf52439676Ca21A244753fA19F9Ea8e;
        } else if (chainId == ChainId.WORLD) {
            poolManager = 0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33;
        } else if (chainId == ChainId.SONEIUM) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        } else if (chainId == ChainId.TEMPO) {
            poolManager = 0x33620f62C5b9B2086dD6b62F4A297A9f30347029;
        } else if (chainId == ChainId.ROBINHOOD) {
            poolManager = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
        } else if (chainId == ChainId.ARC) {
            poolManager = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
        } else if (chainId == ChainId.BASE) {
            poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        } else if (chainId == ChainId.ARBITRUM) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        } else if (chainId == ChainId.AVALANCHE) {
            poolManager = 0x06380C0e0912312B5150364B9DC4542BA0DbBc85;
        } else if (chainId == ChainId.INK) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        } else {
            revert("No pool manager");
        }

        uniswapV4Helpers = new UniswapV4Helpers{ salt: "UniswapV4Helpers" }(poolManager);

        vm.stopBroadcast();
    }
}

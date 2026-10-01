// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniswapV4Helpers } from "../src/helpers/UniswapV4Helpers.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

contract UniswapV4HelpersDeployer is Script {
    function run() public returns (UniswapV4Helpers uniswapV4Helpers, address poolManager, address positionManager) {
        vm.startBroadcast();

        uint256 chainId = block.chainid;

        if (chainId == ChainId.ETHEREUM) {
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        } else if (chainId == ChainId.OPTIMISM) {
            poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
            positionManager = 0x3C3Ea4B57a46241e54610e5f022E5c45859A1017;
        } else if (chainId == ChainId.BINANCE) {
            poolManager = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
            positionManager = 0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b;
        } else if (chainId == ChainId.UNICHAIN) {
            poolManager = 0x1F98400000000000000000000000000000000004;
            positionManager = 0x4529A01c7A0410167c5740C487A8DE60232617bf;
        } else if (chainId == ChainId.POLYGON) {
            poolManager = 0x67366782805870060151383F4BbFF9daB53e5cD6;
            positionManager = 0x1Ec2eBf4F37E7363FDfe3551602425af0B3ceef9;
        } else if (chainId == ChainId.MONAD) {
            poolManager = 0x188d586Ddcf52439676Ca21A244753fA19F9Ea8e;
            positionManager = 0x5b7eC4a94fF9beDb700fb82aB09d5846972F4016;
        } else if (chainId == ChainId.WORLD) {
            poolManager = 0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33;
            positionManager = 0xC585E0f504613b5fBf874F21Af14c65260fB41fA;
        } else if (chainId == ChainId.SONEIUM) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            positionManager = 0x1b35d13a2E2528f192637F14B05f0Dc0e7dEB566;
        } else if (chainId == ChainId.TEMPO) {
            poolManager = 0x33620f62C5b9B2086dD6b62F4A297A9f30347029;
            positionManager = 0x3Fc79444F8EACc1894775493Ff3Fa41f1e35Ce11;
        } else if (chainId == ChainId.ROBINHOOD) {
            poolManager = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
            positionManager = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
        } else if (chainId == ChainId.ARC) {
            poolManager = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
            positionManager = 0x6049c9a0e26405C0985f9E3685C87d0aE917f82B;
        } else if (chainId == ChainId.BASE) {
            poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            positionManager = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
        } else if (chainId == ChainId.ARBITRUM) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            positionManager = 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869;
        } else if (chainId == ChainId.AVALANCHE) {
            poolManager = 0x06380C0e0912312B5150364B9DC4542BA0DbBc85;
            positionManager = 0xB74b1F14d2754AcfcbBe1a221023a5cf50Ab8ACD;
        } else if (chainId == ChainId.INK) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
            positionManager = 0x1b35d13a2E2528f192637F14B05f0Dc0e7dEB566;
        } else {
            revert("No pool manager");
        }

        uniswapV4Helpers = new UniswapV4Helpers{ salt: "UniswapV4Helpers" }(poolManager, positionManager);

        vm.stopBroadcast();
    }
}

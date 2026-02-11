// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { LenderProtocol } from "../src/flashloan/AbstractEnsoFlashloan.sol";

abstract contract FlashloanAdapterConfig {
    uint256 constant ETHEREUM = 1;
    uint256 constant BERACHAIN = 80_094;
    uint256 constant BASE = 8453;
    uint256 constant OPTIMISM = 10;
    uint256 constant ARBITRUM = 42_161;
    uint256 constant HYPER_EVM = 999;
    uint256 constant INK = 57_073;
    uint256 constant POLYGON = 137;
    uint256 constant SONIC = 146;
    uint256 constant UNICHAIN = 130;
    uint256 constant WORLD = 480;
    uint256 constant SONEIUM = 1868;
    uint256 constant PLUME = 98_866;
    uint256 constant KATANA = 747_474;
    uint256 constant MONAD = 143;
    uint256 constant BINANCE = 56;
    uint256 constant GNOSIS = 100;
    uint256 constant ZKSYNC = 324;
    uint256 constant AVALANCHE = 43_114;
    uint256 constant LINEA = 59_144;
    uint256 constant PLASMA = 9745;

    mapping(uint256 chainId => address[] lenders) internal _lenders;
    mapping(uint256 chainId => LenderProtocol[] protocols) internal _protocols;
    mapping(uint256 chainId => address shortcuts) internal _shortcuts;

    function _initConfigs() internal {
        //
        // Ethereum
        //
        _lenders[ETHEREUM].push(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // Aave V3
        _protocols[ETHEREUM].push(LenderProtocol.AaveV3);

        _lenders[ETHEREUM].push(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho
        _protocols[ETHEREUM].push(LenderProtocol.Morpho);

        _lenders[ETHEREUM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ETHEREUM].push(LenderProtocol.BalancerV3);

        _lenders[ETHEREUM].push(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072); // Dolomite
        _protocols[ETHEREUM].push(LenderProtocol.Dolomite);

        _shortcuts[ETHEREUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[ETHEREUM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[ETHEREUM].push(LenderProtocol.UniswapV3);

        //
        // Berachain
        //
        _lenders[BERACHAIN].push(0x24147243f9c08d835C218Cda1e135f8dFD0517D0); // Bend (Morpho fork)
        _protocols[BERACHAIN].push(LenderProtocol.Morpho);

        _lenders[BERACHAIN].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[BERACHAIN].push(LenderProtocol.Dolomite);

        _shortcuts[BERACHAIN] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[BERACHAIN].push(0xD84CBf0B02636E7f53dB9E5e45A616E05d710990); // Kodiak (UniswapV3 fork) Factory
        _protocols[BERACHAIN].push(LenderProtocol.UniswapV3);

        //
        // Base
        //
        _lenders[BASE].push(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5); // Aave V3
        _protocols[BASE].push(LenderProtocol.AaveV3);

        _lenders[BASE].push(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho
        _protocols[BASE].push(LenderProtocol.Morpho);

        _lenders[BASE].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[BASE].push(LenderProtocol.BalancerV3);

        _lenders[BASE].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[BASE].push(LenderProtocol.Dolomite);

        _shortcuts[BASE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[BASE].push(0x33128a8fC17869897dcE68Ed026d694621f6FDfD); // UniswapV3 Factory
        _protocols[BASE].push(LenderProtocol.UniswapV3);

        //
        // HyperEVM
        //
        _lenders[HYPER_EVM].push(0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b); // Hyperlend (Aave V3 fork)
        _protocols[HYPER_EVM].push(LenderProtocol.AaveV3);

        _lenders[HYPER_EVM].push(0x68e37dE8d93d3496ae143F2E900490f6280C57cD); // Morpho
        _protocols[HYPER_EVM].push(LenderProtocol.Morpho);

        _lenders[HYPER_EVM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[HYPER_EVM].push(LenderProtocol.BalancerV3);

        _shortcuts[HYPER_EVM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Arbitrum
        //
        _lenders[ARBITRUM].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[ARBITRUM].push(LenderProtocol.AaveV3);

        _lenders[ARBITRUM].push(0x6c247b1F6182318877311737BaC0844bAa518F5e); // Morpho
        _protocols[ARBITRUM].push(LenderProtocol.Morpho);

        _lenders[ARBITRUM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ARBITRUM].push(LenderProtocol.BalancerV3);

        _lenders[ARBITRUM].push(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072); // Dolomite
        _protocols[ARBITRUM].push(LenderProtocol.Dolomite);

        _shortcuts[ARBITRUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[ARBITRUM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[ARBITRUM].push(LenderProtocol.UniswapV3);

        //
        // Ink
        //
        _lenders[INK].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[INK].push(LenderProtocol.Dolomite);

        _shortcuts[INK] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Optimism
        //
        _lenders[OPTIMISM].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[OPTIMISM].push(LenderProtocol.AaveV3);

        _lenders[OPTIMISM].push(0xce95AfbB8EA029495c66020883F87aaE8864AF92); // Morpho
        _protocols[OPTIMISM].push(LenderProtocol.Morpho);

        _lenders[OPTIMISM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // Uniswap V3 Factory
        _protocols[OPTIMISM].push(LenderProtocol.UniswapV3);

        _shortcuts[OPTIMISM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Polygon
        //
        _lenders[POLYGON].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[POLYGON].push(LenderProtocol.AaveV3);

        _lenders[POLYGON].push(0x1bF0c2541F820E775182832f06c0B7Fc27A25f67); // Morpho
        _protocols[POLYGON].push(LenderProtocol.Morpho);

        _shortcuts[POLYGON] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[POLYGON].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[POLYGON].push(LenderProtocol.UniswapV3);

        //
        // Sonic
        //
        _lenders[SONIC].push(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3); // Aave V3
        _protocols[SONIC].push(LenderProtocol.AaveV3);

        _lenders[SONIC].push(0xd6c916eB7542D0Ad3f18AEd0FCBD50C582cfa95f); // Morpho
        _protocols[SONIC].push(LenderProtocol.Morpho);

        _shortcuts[SONIC] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Unichain
        //
        _lenders[UNICHAIN].push(0x8f5ae9CddB9f68de460C77730b018Ae7E04a140A); // Morpho
        _protocols[UNICHAIN].push(LenderProtocol.Morpho);

        _shortcuts[UNICHAIN] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[UNICHAIN].push(0x1F98400000000000000000000000000000000003); // UniswapV3 Factory
        _protocols[UNICHAIN].push(LenderProtocol.UniswapV3);

        //
        // World
        //
        _lenders[WORLD].push(0xE741BC7c34758b4caE05062794E8Ae24978AF432); // Morpho
        _protocols[WORLD].push(LenderProtocol.Morpho);

        _shortcuts[WORLD] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[WORLD].push(0x7a5028BDa40e7B173C278C5342087826455ea25a); // UniswapV3 Factory
        _protocols[WORLD].push(LenderProtocol.UniswapV3);

        //
        // Soneium
        //
        _lenders[SONEIUM].push(0xE75Fc5eA6e74B824954349Ca351eb4e671ADA53a); // Morpho
        _protocols[SONEIUM].push(LenderProtocol.Morpho);

        _shortcuts[SONEIUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Plume
        //
        _lenders[PLUME].push(0x42b18785CE0Aed7BF7Ca43a39471ED4C0A3e0bB5); // Morpho
        _protocols[PLUME].push(LenderProtocol.Morpho);

        _shortcuts[PLUME] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Katana
        //
        _lenders[KATANA].push(0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc); // Morpho
        _protocols[KATANA].push(LenderProtocol.Morpho);

        _shortcuts[KATANA] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Monad
        //
        _lenders[MONAD].push(0xD5D960E8C380B724a48AC59E2DfF1b2CB4a1eAee); // Morpho
        _protocols[MONAD].push(LenderProtocol.Morpho);

        _shortcuts[MONAD] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Binance
        //
        _lenders[BINANCE].push(0x6807dc923806fE8Fd134338EABCA509979a7e0cB); // Aave V3
        _protocols[BINANCE].push(LenderProtocol.AaveV3);

        _shortcuts[BINANCE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        _lenders[BINANCE].push(0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7); // UniswapV3 Factory
        _protocols[BINANCE].push(LenderProtocol.UniswapV3);

        //
        // Avalanche
        //
        _lenders[AVALANCHE].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[AVALANCHE].push(LenderProtocol.AaveV3);

        _shortcuts[AVALANCHE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Plasma
        //
        _lenders[PLASMA].push(0x925a2A7214Ed92428B5b1B090F80b25700095e12); // Aave V3
        _protocols[PLASMA].push(LenderProtocol.AaveV3);

        _shortcuts[PLASMA] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
    }
}

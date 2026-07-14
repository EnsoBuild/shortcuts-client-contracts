// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { LenderProtocol } from "../src/flashloan/AbstractEnsoFlashloan.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";

abstract contract FlashloanAdapterConfig {
    mapping(uint256 chainId => address[] lenders) internal _lenders;
    mapping(uint256 chainId => LenderProtocol[] protocols) internal _protocols;
    mapping(uint256 chainId => address shortcuts) internal _shortcuts;
    mapping(uint256 chainId => address router) internal _router;

    function _initConfigs() internal {
        //
        // Ethereum
        //
        _lenders[ChainId.ETHEREUM].push(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // Aave V3
        _protocols[ChainId.ETHEREUM].push(LenderProtocol.AaveV3);

        _lenders[ChainId.ETHEREUM].push(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho
        _protocols[ChainId.ETHEREUM].push(LenderProtocol.Morpho);

        _lenders[ChainId.ETHEREUM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ChainId.ETHEREUM].push(LenderProtocol.BalancerV3);

        _lenders[ChainId.ETHEREUM].push(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072); // Dolomite
        _protocols[ChainId.ETHEREUM].push(LenderProtocol.Dolomite);

        _shortcuts[ChainId.ETHEREUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.ETHEREUM] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.ETHEREUM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[ChainId.ETHEREUM].push(LenderProtocol.UniswapV3);

        //
        // Berachain
        //
        _lenders[ChainId.BERACHAIN].push(0x24147243f9c08d835C218Cda1e135f8dFD0517D0); // Bend (Morpho fork)
        _protocols[ChainId.BERACHAIN].push(LenderProtocol.Morpho);

        _lenders[ChainId.BERACHAIN].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[ChainId.BERACHAIN].push(LenderProtocol.Dolomite);

        _shortcuts[ChainId.BERACHAIN] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.BERACHAIN] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.BERACHAIN].push(0xD84CBf0B02636E7f53dB9E5e45A616E05d710990); // Kodiak (UniswapV3 fork) Factory
        _protocols[ChainId.BERACHAIN].push(LenderProtocol.UniswapV3);

        //
        // Base
        //
        _lenders[ChainId.BASE].push(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5); // Aave V3
        _protocols[ChainId.BASE].push(LenderProtocol.AaveV3);

        _lenders[ChainId.BASE].push(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho
        _protocols[ChainId.BASE].push(LenderProtocol.Morpho);

        _lenders[ChainId.BASE].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ChainId.BASE].push(LenderProtocol.BalancerV3);

        _lenders[ChainId.BASE].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[ChainId.BASE].push(LenderProtocol.Dolomite);

        _shortcuts[ChainId.BASE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.BASE] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.BASE].push(0x33128a8fC17869897dcE68Ed026d694621f6FDfD); // UniswapV3 Factory
        _protocols[ChainId.BASE].push(LenderProtocol.UniswapV3);

        //
        // MegaETH
        //
        _lenders[ChainId.MEGAETH].push(0x7e324AbC5De01d112AfC03a584966ff199741C28); // Aave V3
        _protocols[ChainId.MEGAETH].push(LenderProtocol.AaveV3);

        _lenders[ChainId.MEGAETH].push(0x68b34591f662508076927803c567Cc8006988a09); // Kumbaya (UniswapV3 fork) Factory
        _protocols[ChainId.MEGAETH].push(LenderProtocol.UniswapV3);

        _shortcuts[ChainId.MEGAETH] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.MEGAETH] = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // EnsoRouter

        //
        // HyperEVM
        //
        _lenders[ChainId.HYPER].push(0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b); // Hyperlend (Aave V3 fork)
        _protocols[ChainId.HYPER].push(LenderProtocol.AaveV3);

        _lenders[ChainId.HYPER].push(0x68e37dE8d93d3496ae143F2E900490f6280C57cD); // Morpho
        _protocols[ChainId.HYPER].push(LenderProtocol.Morpho);

        _lenders[ChainId.HYPER].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ChainId.HYPER].push(LenderProtocol.BalancerV3);

        _shortcuts[ChainId.HYPER] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.HYPER] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Arbitrum
        //
        _lenders[ChainId.ARBITRUM].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[ChainId.ARBITRUM].push(LenderProtocol.AaveV3);

        _lenders[ChainId.ARBITRUM].push(0x6c247b1F6182318877311737BaC0844bAa518F5e); // Morpho
        _protocols[ChainId.ARBITRUM].push(LenderProtocol.Morpho);

        _lenders[ChainId.ARBITRUM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ChainId.ARBITRUM].push(LenderProtocol.BalancerV3);

        _lenders[ChainId.ARBITRUM].push(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072); // Dolomite
        _protocols[ChainId.ARBITRUM].push(LenderProtocol.Dolomite);

        _shortcuts[ChainId.ARBITRUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.ARBITRUM] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.ARBITRUM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[ChainId.ARBITRUM].push(LenderProtocol.UniswapV3);

        //
        // Ink
        //
        _lenders[ChainId.INK].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[ChainId.INK].push(LenderProtocol.Dolomite);

        _shortcuts[ChainId.INK] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.INK] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Optimism
        //
        _lenders[ChainId.OPTIMISM].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[ChainId.OPTIMISM].push(LenderProtocol.AaveV3);

        _lenders[ChainId.OPTIMISM].push(0xce95AfbB8EA029495c66020883F87aaE8864AF92); // Morpho
        _protocols[ChainId.OPTIMISM].push(LenderProtocol.Morpho);

        _lenders[ChainId.OPTIMISM].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // Uniswap V3 Factory
        _protocols[ChainId.OPTIMISM].push(LenderProtocol.UniswapV3);

        _shortcuts[ChainId.OPTIMISM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.OPTIMISM] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Polygon
        //
        _lenders[ChainId.POLYGON].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[ChainId.POLYGON].push(LenderProtocol.AaveV3);

        _lenders[ChainId.POLYGON].push(0x1bF0c2541F820E775182832f06c0B7Fc27A25f67); // Morpho
        _protocols[ChainId.POLYGON].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.POLYGON] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.POLYGON] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.POLYGON].push(0x1F98431c8aD98523631AE4a59f267346ea31F984); // UniswapV3 Factory
        _protocols[ChainId.POLYGON].push(LenderProtocol.UniswapV3);

        //
        // Sonic
        //
        _lenders[ChainId.SONIC].push(0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3); // Aave V3
        _protocols[ChainId.SONIC].push(LenderProtocol.AaveV3);

        _lenders[ChainId.SONIC].push(0xd6c916eB7542D0Ad3f18AEd0FCBD50C582cfa95f); // Morpho
        _protocols[ChainId.SONIC].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.SONIC] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.SONIC] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Unichain
        //
        _lenders[ChainId.UNICHAIN].push(0x8f5ae9CddB9f68de460C77730b018Ae7E04a140A); // Morpho
        _protocols[ChainId.UNICHAIN].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.UNICHAIN] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.UNICHAIN] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.UNICHAIN].push(0x1F98400000000000000000000000000000000003); // UniswapV3 Factory
        _protocols[ChainId.UNICHAIN].push(LenderProtocol.UniswapV3);

        //
        // World
        //
        _lenders[ChainId.WORLD].push(0xE741BC7c34758b4caE05062794E8Ae24978AF432); // Morpho
        _protocols[ChainId.WORLD].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.WORLD] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.WORLD] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.WORLD].push(0x7a5028BDa40e7B173C278C5342087826455ea25a); // UniswapV3 Factory
        _protocols[ChainId.WORLD].push(LenderProtocol.UniswapV3);

        //
        // Soneium
        //
        _lenders[ChainId.SONEIUM].push(0xE75Fc5eA6e74B824954349Ca351eb4e671ADA53a); // Morpho
        _protocols[ChainId.SONEIUM].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.SONEIUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.SONEIUM] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Plume
        //
        _lenders[ChainId.PLUME].push(0x42b18785CE0Aed7BF7Ca43a39471ED4C0A3e0bB5); // Morpho
        _protocols[ChainId.PLUME].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.PLUME] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.PLUME] = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F; // EnsoRouter

        //
        // Katana
        //
        _lenders[ChainId.KATANA].push(0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc); // Morpho
        _protocols[ChainId.KATANA].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.KATANA] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.KATANA] = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F; // EnsoRouter

        //
        // Monad
        //
        _lenders[ChainId.MONAD].push(0xD5D960E8C380B724a48AC59E2DfF1b2CB4a1eAee); // Morpho
        _protocols[ChainId.MONAD].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.MONAD] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.MONAD] = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // EnsoRouter

        //
        // Binance
        //
        _lenders[ChainId.BINANCE].push(0x6807dc923806fE8Fd134338EABCA509979a7e0cB); // Aave V3
        _protocols[ChainId.BINANCE].push(LenderProtocol.AaveV3);

        _shortcuts[ChainId.BINANCE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.BINANCE] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        _lenders[ChainId.BINANCE].push(0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7); // UniswapV3 Factory
        _protocols[ChainId.BINANCE].push(LenderProtocol.UniswapV3);

        //
        // Avalanche
        //
        _lenders[ChainId.AVALANCHE].push(0x794a61358D6845594F94dc1DB02A252b5b4814aD); // Aave V3
        _protocols[ChainId.AVALANCHE].push(LenderProtocol.AaveV3);

        _shortcuts[ChainId.AVALANCHE] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.AVALANCHE] = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // EnsoRouter

        //
        // Plasma
        //
        _lenders[ChainId.PLASMA].push(0x925a2A7214Ed92428B5b1B090F80b25700095e12); // Aave V3
        _protocols[ChainId.PLASMA].push(LenderProtocol.AaveV3);

        _shortcuts[ChainId.PLASMA] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.PLASMA] = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // EnsoRouter

        //
        // Robinhood
        //
        _lenders[ChainId.ROBINHOOD].push(0x1f7d7550B1b028f7571E69A784071F0205FD2EfA); // UniswapV3 Factory
        _protocols[ChainId.ROBINHOOD].push(LenderProtocol.UniswapV3);

        _lenders[ChainId.ROBINHOOD].push(0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010); // Morpho
        _protocols[ChainId.ROBINHOOD].push(LenderProtocol.Morpho);

        _shortcuts[ChainId.ROBINHOOD] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
        _router[ChainId.ROBINHOOD] = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // EnsoRouter
    }
}

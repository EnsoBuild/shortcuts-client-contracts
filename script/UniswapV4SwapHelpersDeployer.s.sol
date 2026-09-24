// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

import { UniswapV4SwapHelpers } from "../src/helpers/UniswapV4SwapHelpers.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

/// @notice Deploys the canonical UniswapV4SwapHelpers: 5-field ExactInputSingleParams, as decoded by the
///         stock UniversalRouter (Tempo included, verified source). Robinhood (4663) and Arc (5042) run a
///         forked router whose V4Router adds `minHopPriceX36`; they are served by UniswapV4SwapHelpersMinHopPrice
///         and its own deployer, and must not be added here.
contract UniswapV4SwapHelpersDeployer is Script {
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(uint256 => address) public universalRouters;

    constructor() {
        // Ethereum
        universalRouters[ChainId.ETHEREUM] = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

        // Optimism
        universalRouters[ChainId.OPTIMISM] = 0x851116D9223fabED8E56C0E6b8Ad0c31d98B3507;

        // Binance
        universalRouters[ChainId.BINANCE] = 0x1906c1d672b88cD1B9aC7593301cA990F94Eae07;

        // Unichain
        universalRouters[ChainId.UNICHAIN] = 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3;

        // Polygon
        universalRouters[ChainId.POLYGON] = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;

        // Monad
        universalRouters[ChainId.MONAD] = 0x0D97Dc33264bfC1c226207428A79b26757fb9dc3;

        // World
        universalRouters[ChainId.WORLD] = 0x8ac7bEE993bb44dAb564Ea4bc9EA67Bf9Eb5e743;

        // Soneium
        universalRouters[ChainId.SONEIUM] = 0x4cded7Edf52c8AA5259A54Ec6a3CE7C6D2a455Df;

        // Tempo
        universalRouters[ChainId.TEMPO] = 0xA2Dc7d0266f0CC50b3eEaF36c9BFCeCFF1BEea91;

        // Base
        universalRouters[ChainId.BASE] = 0x6fF5693b99212Da76ad316178A184AB56D299b43;

        // Arbitrum
        universalRouters[ChainId.ARBITRUM] = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;

        // Avalanche
        universalRouters[ChainId.AVALANCHE] = 0x94b75331AE8d42C1b61065089B7d48FE14aA73b7;

        // Ink
        universalRouters[ChainId.INK] = 0x112908daC86e20e7241B0927479Ea3Bf935d1fa0;
    }

    function run() public returns (UniswapV4SwapHelpers uniswapV4SwapHelpers, address universalRouter) {
        universalRouter = universalRouters[block.chainid];
        require(universalRouter != address(0), "No universal router set");

        vm.startBroadcast();

        uniswapV4SwapHelpers =
            new UniswapV4SwapHelpers{ salt: "UniswapV4SwapHelpers" }(IUniversalRouter(universalRouter), PERMIT2);

        vm.stopBroadcast();
    }
}

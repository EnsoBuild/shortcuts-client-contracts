// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

import { UniswapV4SwapHelpersMinHopPrice } from "../src/helpers/UniswapV4SwapHelpersMinHopPrice.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

/// @notice Deploys UniswapV4SwapHelpersMinHopPrice for chains whose forked UniversalRouter adds
///         `minHopPriceX36` to ExactInputSingleParams. Stock-router chains (Tempo included) use
///         UniswapV4SwapHelpersDeployer instead.
contract UniswapV4SwapHelpersMinHopPriceDeployer is Script {
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(uint256 => address) public universalRouters;

    constructor() {
        // Robinhood
        universalRouters[ChainId.ROBINHOOD] = 0x8876789976dEcBfCbBbe364623C63652db8C0904;

        // Arc
        universalRouters[ChainId.ARC] = 0x4fcA4a51Ab4F23A7447b3284fBd7D73289A89Fb1;
    }

    function run() public returns (UniswapV4SwapHelpersMinHopPrice uniswapV4SwapHelpers, address universalRouter) {
        universalRouter = universalRouters[block.chainid];
        require(universalRouter != address(0), "No universal router set");

        vm.startBroadcast();

        uniswapV4SwapHelpers = new UniswapV4SwapHelpersMinHopPrice{ salt: "UniswapV4SwapHelpersMinHopPrice" }(
            IUniversalRouter(universalRouter), PERMIT2
        );

        vm.stopBroadcast();
    }
}

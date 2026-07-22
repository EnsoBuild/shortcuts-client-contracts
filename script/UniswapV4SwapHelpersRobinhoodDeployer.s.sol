// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

import { UniswapV4SwapHelpersRobinhood } from "../src/helpers/UniswapV4SwapHelpersRobinhood.sol";
import { Script } from "forge-std/Script.sol";

contract UniswapV4SwapHelpersRobinhoodDeployer is Script {
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(uint256 => address) public universalRouters;

    constructor() {
        // Robinhood
        universalRouters[4663] = 0x8876789976dEcBfCbBbe364623C63652db8C0904;
    }

    function run() public returns (UniswapV4SwapHelpersRobinhood uniswapV4SwapHelpers, address universalRouter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        universalRouter = universalRouters[block.chainid];
        require(universalRouter != address(0), "No universal router set");

        vm.startBroadcast(deployerPrivateKey);

        uniswapV4SwapHelpers = new UniswapV4SwapHelpersRobinhood{ salt: "UniswapV4SwapHelpersRobinhood" }(
            IUniversalRouter(universalRouter), PERMIT2
        );

        vm.stopBroadcast();
    }
}

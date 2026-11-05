// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import { PropAMMSwapHelpers } from "../src/helpers/PropAMMSwapHelpers.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

/// @notice Deploys PropAMMSwapHelpers on Ethereum, the only chain with Titan pAMM venues.
contract PropAMMSwapHelpersDeployer is Script {
    IPoolManager constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    function run() public returns (PropAMMSwapHelpers propAMMSwapHelpers) {
        require(block.chainid == ChainId.ETHEREUM, "Ethereum only");

        vm.startBroadcast();

        propAMMSwapHelpers = new PropAMMSwapHelpers{ salt: "PropAMMSwapHelpers" }(POOL_MANAGER);

        vm.stopBroadcast();
    }
}

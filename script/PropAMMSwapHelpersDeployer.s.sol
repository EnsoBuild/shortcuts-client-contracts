// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../src/helpers/PropAMMSwapHelpers.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

/// @notice Deploys PropAMMSwapHelpers on Ethereum, the only chain with Titan pAMM venues.
contract PropAMMSwapHelpersDeployer is Script {
    function run() public returns (PropAMMSwapHelpers propAMMSwapHelpers) {
        require(block.chainid == ChainId.ETHEREUM, "Ethereum only");

        vm.startBroadcast();

        propAMMSwapHelpers = new PropAMMSwapHelpers{ salt: "PropAMMSwapHelpers" }();

        vm.stopBroadcast();
    }
}

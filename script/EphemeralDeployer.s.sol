// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { ChainId } from "../src/libraries/ChainOwner.sol";
import { Script } from "forge-std/Script.sol";

/// Salted CREATE2 with no constructor arguments: one factory address, and so one address per
/// intent tree, on every chain. The factory links IntentHash and IntentEvaluator, which must be
/// deployed deterministically first so their linked addresses are identical everywhere too.
contract EphemeralDeployer is Script {
    function run() public returns (EphemeralFactory factory) {
        if (block.chainid == ChainId.ZKSYNC) {
            revert("unsupported chain"); // zkSync's CREATE2 derivation differs
        }
        vm.startBroadcast();
        factory = new EphemeralFactory{ salt: "EphemeralFactory" }();
        vm.stopBroadcast();
    }
}

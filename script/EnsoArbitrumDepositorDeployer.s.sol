// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoArbitrumDepositor } from "../src/bridge/EnsoArbitrumDepositor.sol";
import { ChainId, ChainOwner } from "../src/libraries/ChainOwner.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoArbitrumDepositorDeployer is Script {
    error UnsupportedChainId(uint256 chainId);

    function run() public returns (address depositor, address owner) {
        uint256 chainId = block.chainid;
        if (chainId != ChainId.ETHEREUM) {
            revert UnsupportedChainId(chainId);
        }

        owner = ChainOwner.ownerFor(chainId);

        vm.startBroadcast();

        depositor = address(new EnsoArbitrumDepositor{ salt: "EnsoArbitrumDepositor" }(owner));

        vm.stopBroadcast();
    }
}

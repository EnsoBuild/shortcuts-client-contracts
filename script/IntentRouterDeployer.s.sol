// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../src/EnsoShortcuts.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { IntentRouter } from "../src/router/IntentRouter.sol";
import { Script } from "forge-std/Script.sol";

contract IntentRouterDeployer is Script {
    error UnconfiguredChain(uint256 chainId);

    function run() public returns (IntentRouter router, EnsoShortcuts shortcuts) {
        address keeper = getKeeper(block.chainid);
        require(keeper.code.length > 0, "keeper not deployed");

        vm.startBroadcast();
        router = new IntentRouter{ salt: "IntentRouter" }(keeper);
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
        vm.stopBroadcast();
    }

    /// @notice The chain's KeeperWallet (broadcast/KeeperWalletDeployer.s.sol). The keeper is an
    ///         immutable, so an unconfigured chain reverts rather than deploying against a placeholder.
    function getKeeper(uint256 chainId) internal pure returns (address keeper) {
        if (chainId == ChainId.ETHEREUM || chainId == ChainId.OPTIMISM) {
            keeper = 0x7AcC93938D4Fb2F8bf7A8E4344f8160c81697f07;
        } else if (chainId == ChainId.ARBITRUM || chainId == ChainId.ROBINHOOD || chainId == ChainId.HYPER) {
            keeper = 0xDCe034741d04b01798f779ECE114bcE2b8Df2C1D;
        } else {
            revert UnconfiguredChain(chainId);
        }
    }
}

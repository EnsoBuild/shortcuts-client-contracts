// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { ChainId } from "../src/libraries/ChainOwner.sol";
import { Script } from "forge-std/Script.sol";

contract EphemeralDeployer is Script {
    function run() public returns (EphemeralFactory factory) {
        address router = getRouter(block.chainid);
        require(router.code.length > 0, "router not deployed");

        vm.startBroadcast();
        factory = new EphemeralFactory{ salt: "EphemeralFactory" }(router);
        vm.stopBroadcast();
    }

    function getRouter(uint256 chainId) internal pure returns (address router) {
        if (chainId == ChainId.ZKSYNC) {
            revert("unsupported chain");
        } else if (chainId == ChainId.KATANA || chainId == ChainId.PLUME) {
            router = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F;
        } else if (chainId == ChainId.LINEA) {
            router = 0xA146d46823f3F594B785200102Be5385CAfCE9B5;
        } else if (
            chainId == ChainId.PLASMA || chainId == ChainId.MONAD || chainId == ChainId.MEGAETH
                || chainId == ChainId.ROBINHOOD || chainId == ChainId.ETHERLINK || chainId == ChainId.TEMPO
        ) {
            router = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7;
        } else if (chainId == ChainId.SEI) {
            router = 0x300b3D30aaBf46b05983284f0297D966E92bbeB2;
        } else {
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf; // default
        }
    }
}

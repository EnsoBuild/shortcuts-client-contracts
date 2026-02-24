// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoRouterFlashloanAdapter } from "../src/flashloan/EnsoRouterFlashloanAdapter.sol";
import { EnsoSafeFlashloanAdapter } from "../src/flashloan/EnsoSafeFlashloanAdapter.sol";
import { EnsoWalletFlashloanAdapter } from "../src/flashloan/EnsoWalletFlashloanAdapter.sol";
import { FlashloanAdapterConfig, LenderProtocol } from "./FlashloanAdapterConfig.s.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoWalletFlashloanAdapterDeployer is Script, FlashloanAdapterConfig {
    function run() public returns (EnsoRouterFlashloanAdapter routerAdapter, EnsoSafeFlashloanAdapter safeAdapter, EnsoWalletFlashloanAdapter walletAdapter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        _initConfigs();

        address[] storage lenders = _lenders[block.chainid];
        LenderProtocol[] storage protocols = _protocols[block.chainid];
        address shortcuts = _shortcuts[block.chainid];
        address router = _router[block.chainid];

        require(lenders.length > 0, "Unsupported chain");

        vm.startBroadcast(deployerPrivateKey);

        address owner = vm.envOr("OWNER", vm.addr(deployerPrivateKey));

        if (router != address(0)) {
            routerAdapter = new EnsoRouterFlashloanAdapter{ salt: "EnsoRouterFlashloanAdapter" }(lenders, protocols, router, owner);
        }
        if (shortcuts != address(0)) {
            safeAdapter = new EnsoSafeFlashloanAdapter{ salt: "EnsoSafeFlashloanAdapter" }(lenders, protocols, shortcuts, owner);
        }
        walletAdapter = new EnsoWalletFlashloanAdapter{ salt: "EnsoWalletFlashloanAdapter" }(lenders, protocols, owner);
    
        

        vm.stopBroadcast();
    }
}

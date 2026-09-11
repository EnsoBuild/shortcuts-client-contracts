// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoRouterFlashloanAdapter } from "../src/flashloan/EnsoRouterFlashloanAdapter.sol";
import { EnsoSafeFlashloanAdapter } from "../src/flashloan/EnsoSafeFlashloanAdapter.sol";
import { EnsoWalletFlashloanAdapter } from "../src/flashloan/EnsoWalletFlashloanAdapter.sol";
import { ChainOwner } from "../src/libraries/ChainOwner.sol";
import { FlashloanAdapterConfig, LenderProtocol } from "./FlashloanAdapterConfig.s.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoWalletFlashloanAdapterDeployer is Script, FlashloanAdapterConfig {
    function run()
        public
        returns (
            EnsoRouterFlashloanAdapter routerAdapter,
            EnsoSafeFlashloanAdapter safeAdapter,
            EnsoWalletFlashloanAdapter walletAdapter
        )
    {
        _initConfigs();

        address[] storage lenders = _lenders[block.chainid];
        LenderProtocol[] storage protocols = _protocols[block.chainid];
        address shortcuts = _shortcuts[block.chainid];
        address router = _router[block.chainid];

        require(lenders.length > 0, "Unsupported chain");

        // Lenders are constructor arguments and the adapters expose removeLender but no
        // addLender, so whatever is passed here is permanent: an unresolved placeholder would
        // both register address(0) as a trusted lender and make the real lender unaddable
        // without redeploying to a different CREATE2 address.
        for (uint256 i = 0; i < lenders.length; i++) {
            // forge-lint: disable-next-line(require-revert-in-loop)
            require(lenders[i] != address(0), "Lender address not configured");
        }

        vm.startBroadcast();

        address owner = ChainOwner.ownerFor(block.chainid);

        if (router != address(0)) {
            routerAdapter =
                new EnsoRouterFlashloanAdapter{ salt: "EnsoRouterFlashloanAdapter" }(lenders, protocols, router, owner);
        }
        if (shortcuts != address(0)) {
            safeAdapter =
                new EnsoSafeFlashloanAdapter{ salt: "EnsoSafeFlashloanAdapter" }(lenders, protocols, shortcuts, owner);
        }
        walletAdapter = new EnsoWalletFlashloanAdapter{ salt: "EnsoWalletFlashloanAdapter" }(lenders, protocols, owner);

        vm.stopBroadcast();
    }
}

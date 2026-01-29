// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/flashloan/EnsoSafeFlashloanAdapter.sol";
import "./FlashloanAdapterConfig.s.sol";
import "forge-std/Script.sol";

contract EnsoSafeFlashloanAdapterDeployer is Script, FlashloanAdapterConfig {
    function run() public returns (EnsoSafeFlashloanAdapter adapter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        _initConfigs();

        address[] storage lenders = _lenders[block.chainid];
        LenderProtocol[] storage protocols = _protocols[block.chainid];
        address shortcuts = _shortcuts[block.chainid];

        require(lenders.length > 0, "Unsupported chain");
        require(shortcuts != address(0), "Shortcuts not configured");

        vm.startBroadcast(deployerPrivateKey);

        address owner = vm.envOr("OWNER", vm.addr(deployerPrivateKey));
        adapter = new EnsoSafeFlashloanAdapter{ salt: "EnsoSafeFlashloanAdapter" }(lenders, protocols, shortcuts, owner);

        vm.stopBroadcast();
    }
}

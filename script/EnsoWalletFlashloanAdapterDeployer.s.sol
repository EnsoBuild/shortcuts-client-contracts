// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/flashloan/EnsoWalletFlashloanAdapter.sol";
import "./FlashloanAdapterConfig.s.sol";
import "forge-std/Script.sol";

contract EnsoWalletFlashloanAdapterDeployer is Script, FlashloanAdapterConfig {
    function run() public returns (EnsoWalletFlashloanAdapter adapter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        _initConfigs();

        address[] storage lenders = _lenders[block.chainid];
        LenderProtocol[] storage protocols = _protocols[block.chainid];

        require(lenders.length > 0, "Unsupported chain");

        vm.startBroadcast(deployerPrivateKey);

        address owner = vm.envOr("OWNER", vm.addr(deployerPrivateKey));
        adapter = new EnsoWalletFlashloanAdapter{ salt: "EnsoWalletFlashloanAdapter" }(lenders, protocols, owner);

        vm.stopBroadcast();
    }
}

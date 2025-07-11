// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/delegate/EnsoReceiver.sol";
import "../src/factory/ERC4337CloneFactory.sol";
import "forge-std/Script.sol";

contract EnsoReceiverDeployer is Script {
    address OWNER = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA;
    address ENTRY_POINT = address(0); // TODO

    function run() public returns (EnsoReceiver implementation, ERC4337CloneFactory factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        implementation = new EnsoReceiver{ salt: "EnsoReceiver" }();
        factory = new ERC4337CloneFactory{ salt: "ERC4337CloneFactory" }(OWNER);
        factory.initialize(address(implementation), ENTRY_POINT);

        vm.stopBroadcast();
    }
}

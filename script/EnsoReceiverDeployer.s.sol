// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/delegate/EnsoReceiver.sol";
import "../src/factory/ERC4337CloneFactory.sol";
import "../src/paymaster/SignaturePaymaster.sol";
import "forge-std/Script.sol";

contract EnsoReceiverDeployer is Script {
    address ENTRY_POINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
    address ENTRY_POINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    address OWNER = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA; // TODO: set multisig as owner for production deployment
    address BACKEND_SIGNER = 0xFE503EE14863F6aCEE10BCdc66aC5e2301b3A946; // TODO: in production the signer will have to set via the multisig

    function run() public returns (EnsoReceiver implementation, ERC4337CloneFactory factory, SignaturePaymaster paymaster) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address entryPoint = ENTRY_POINT_V7;
        implementation = new EnsoReceiver{ salt: "EnsoReceiver" }();
        implementation.initialize(address(0), address(0), address(0)); // brick the implementation
        factory = new ERC4337CloneFactory{ salt: "ERC4337CloneFactory" }(address(implementation), entryPoint);
        paymaster = new SignaturePaymaster{ salt: "SignaturePaymaster" }(IEntryPoint(entryPoint), OWNER);
        paymaster.setSigner(BACKEND_SIGNER, true);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../src/factory/ERC4337CloneFactory.sol";
import { ChainOwner } from "../src/libraries/ChainOwner.sol";
import { SignaturePaymaster } from "../src/paymaster/SignaturePaymaster.sol";
import { IEntryPoint } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoReceiverAndPaymasterDeployer is Script {
    address ENTRY_POINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address BACKEND_SIGNER = 0x89B3c70f6dF4Fc6Ba0613de208c9da5132b8ecc2;

    function run()
        public
        returns (EnsoReceiver implementation, ERC4337CloneFactory factory, SignaturePaymaster paymaster)
    {
        vm.startBroadcast();

        address owner = ChainOwner.ownerFor(block.chainid);
        address deployer = msg.sender;
        address entryPoint = ENTRY_POINT_V7;
        implementation = new EnsoReceiver{ salt: "EnsoReceiver" }();
        implementation.initialize(address(0), address(0), address(0)); // brick the implementation
        factory = new ERC4337CloneFactory{ salt: "ERC4337CloneFactory" }(address(implementation), entryPoint);
        paymaster = new SignaturePaymaster{ salt: "SignaturePaymaster" }(IEntryPoint(entryPoint), deployer);
        paymaster.setSigner(BACKEND_SIGNER, true);
        paymaster.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../../../../../src/factory/ERC4337CloneFactory.sol";
import { ERC4337CloneFactory_Unit_Concrete_Test } from "./ERC4337CloneFactory.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract ERC4337CloneFactory_Deploy_Unit_Concrete_Test is ERC4337CloneFactory_Unit_Concrete_Test {
    function test_WhenEnsoReceiverDoesNotExist() external {
        address expectedEnsoReceiverAddr = s_cloneFactory.getAddress(s_owner);

        // it should emit CloneDeployed event
        vm.expectEmit(address(s_cloneFactory));
        emit ERC4337CloneFactory.CloneDeployed(expectedEnsoReceiverAddr, s_owner, s_owner);
        address payable clone = payable(s_cloneFactory.deploy(s_owner));

        // it should deploy clone
        assertEq(clone, expectedEnsoReceiverAddr);
        assertTrue(expectedEnsoReceiverAddr.code.length > 0);

        // it should initialize clone
        assertTrue(EnsoReceiver(clone).owner() == s_owner);
        assertTrue(EnsoReceiver(clone).signer() == s_owner);
        assertTrue(EnsoReceiver(clone).entryPoint() == s_entryPoint);
    }

    function test_WhenEnsoReceiverAlreadyExists() external {
        address payable clone = payable(s_cloneFactory.deploy(s_owner));

        address payable newClone = payable(s_cloneFactory.deploy(s_owner));

        // it should return clone
        assertEq(newClone, clone);
    }
}

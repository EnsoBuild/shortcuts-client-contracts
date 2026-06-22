// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";

contract EnsoCCIPReceiverV2_SupportsInterface_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test {
    function test_WhenInterfaceIdIsTypeIAny2EVMMessageReceiver() external {
        // Act & Assert
        // it should return true
        vm.prank(s_account1);
        assertTrue(s_ensoCcipReceiver.supportsInterface(s_ensoCcipReceiver.ccipReceive.selector));
    }

    modifier whenInterfaceIdIsNotTypeIAny2EVMMessageReceiver() {
        _;
    }

    function test_WhenInterfaceIdIsTypeIERC165() external whenInterfaceIdIsNotTypeIAny2EVMMessageReceiver {
        // Act & Assert
        // it should return true
        vm.prank(s_account1);
        assertTrue(s_ensoCcipReceiver.supportsInterface(s_ensoCcipReceiver.supportsInterface.selector));
    }

    function test_WhenInterfaceIdIsNotTypeIERC165() external whenInterfaceIdIsNotTypeIAny2EVMMessageReceiver {
        // Act & Assert
        // it should return false
        vm.prank(s_account1);
        assertFalse(s_ensoCcipReceiver.supportsInterface(bytes4(hex"FFFFFFFF")));
    }
}

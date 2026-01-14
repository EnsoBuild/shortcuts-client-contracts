// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { IAny2EVMMessageReceiver } from "chainlink-ccip/interfaces/IAny2EVMMessageReceiver.sol";
import { IERC165 } from "openzeppelin-contracts/utils/introspection/IERC165.sol";

contract EnsoCCIPReceiver_SupportsInterface_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
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

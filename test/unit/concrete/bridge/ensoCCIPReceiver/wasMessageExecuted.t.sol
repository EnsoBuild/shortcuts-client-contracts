// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";

contract EnsoCCIPReceiver_WasMessageExecuted_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_ShouldReturnWhetherMessageWasExecuted() external {
        // Act & Assert
        // it should return whether message was executed
        vm.prank(s_account1);
        assertFalse(s_ensoCcipReceiver.wasMessageExecuted(bytes32(uint256(1))));
    }
}

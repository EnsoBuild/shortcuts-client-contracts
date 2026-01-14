// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";

contract EnsoCCIPReceiver_TypeAndVersion_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_ShouldReturnCurrentTypeAndSemanticVersion() external {
        // Act & Assert
        // it should return current type and semantic version
        vm.prank(s_account1);
        assertEq(keccak256(bytes(s_ensoCcipReceiver.typeAndVersion())), keccak256(bytes("EnsoCCIPReceiver 1.0.0")));
    }
}

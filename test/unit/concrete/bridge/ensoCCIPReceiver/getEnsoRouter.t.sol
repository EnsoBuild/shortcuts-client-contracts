// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";

contract EnsoCCIPReceiver_GetEnsoRouter_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_ShouldReturnEnsoRouterAddress() external {
        // Act & Assert
        // it should return EnsoRouter address
        vm.prank(s_account1);
        assertEq(s_ensoCcipReceiver.getEnsoRouter(), address(s_ensoRouter));
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";

contract EnsoCCIPReceiverV2_GetEnsoRouter_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test {
    function test_ShouldReturnEnsoRouterAddress() external {
        // Act & Assert
        // it should return EnsoRouter address
        vm.prank(s_account1);
        assertEq(s_ensoCcipReceiver.getEnsoRouter(), address(s_ensoRouter));
    }
}

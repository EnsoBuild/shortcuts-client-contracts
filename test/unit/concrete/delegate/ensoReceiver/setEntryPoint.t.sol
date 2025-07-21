// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract EnsoReceiver_SetEntryPoint_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.setEntryPoint(s_account3);
    }

    function test_WhenCallerIsOwner() external {
        // it should emit NewEntryPoint
        vm.prank(s_owner);
        vm.expectEmit(address(s_ensoReceiver));
        emit EnsoReceiver.NewEntryPoint(s_account3);
        s_ensoReceiver.setEntryPoint(s_account3);

        // it should set entryPoint
        assertEq(s_ensoReceiver.entryPoint(), s_account3);
    }
}

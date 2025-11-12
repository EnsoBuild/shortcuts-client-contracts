// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiver_Pause_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account1));
        vm.prank(s_account1);
        s_ensoCcipReceiver.pause();
    }

    function test_WhenCallerIsOwner() external {
        // Act
        vm.prank(s_owner);
        s_ensoCcipReceiver.pause();

        // Assert
        // it should pause the contract
        assertTrue(s_ensoCcipReceiver.paused());
    }
}

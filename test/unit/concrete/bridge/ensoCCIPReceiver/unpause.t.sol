// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiver_Unpause_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(s_owner);
        s_ensoCcipReceiver.pause();
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account1));
        vm.prank(s_account1);
        s_ensoCcipReceiver.unpause();
    }

    function test_WhenCallerIsOwner() external {
        // Act
        vm.prank(s_owner);
        s_ensoCcipReceiver.unpause();

        // Assert
        // it should unpause the contract
        assertFalse(s_ensoCcipReceiver.paused());
    }
}

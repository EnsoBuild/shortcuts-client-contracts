// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiver_RenounceOwnership_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account2));
        vm.prank(s_account2);
        s_ensoCcipReceiver.renounceOwnership();
    }

    function test_WhenCallerIsOwner() external {
        // Act
        vm.prank(s_owner);
        s_ensoCcipReceiver.renounceOwnership();

        // Assert
        // it should transfer ownership to zero address
        assertEq(s_ensoCcipReceiver.owner(), address(0));
    }
}

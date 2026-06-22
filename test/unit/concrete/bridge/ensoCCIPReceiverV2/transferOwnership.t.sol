// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiverV2_TransferOwnership_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account2));
        vm.prank(s_account2);
        s_ensoCcipReceiver.transferOwnership(s_account2);
    }

    function test_WhenCallerIsOwner() external {
        // Act
        vm.prank(s_owner);
        s_ensoCcipReceiver.transferOwnership(s_account2);

        // Assert
        // it should start ownership transfer
        assertEq(s_ensoCcipReceiver.owner(), s_owner);
        assertEq(s_ensoCcipReceiver.pendingOwner(), s_account2);
    }
}

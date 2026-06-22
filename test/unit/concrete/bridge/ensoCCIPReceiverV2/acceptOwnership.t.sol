// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiverV2_AcceptOwnership_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(s_owner);
        s_ensoCcipReceiver.transferOwnership(s_account2);
    }

    function test_RevertWhen_CallerIsNotPendingOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account1));
        vm.prank(s_account1);
        s_ensoCcipReceiver.acceptOwnership();
    }

    function test_WhenCallerIsPendingOwner() external {
        // Act
        vm.prank(s_account2);
        s_ensoCcipReceiver.acceptOwnership();

        // Assert
        // it should transfer ownership
        assertEq(s_ensoCcipReceiver.owner(), s_account2);
    }
}

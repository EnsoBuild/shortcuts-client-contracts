// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_AcceptOwnership_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(s_owner);
        s_signaturePaymaster.transferOwnership(s_account3);
    }

    function test_RevertWhen_CallerIsNotPendingOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account4));
        vm.prank(s_account4);
        s_signaturePaymaster.acceptOwnership();
    }

    function test_WhenCallerIsPendingOwner() external {
        vm.prank(s_account3);
        s_signaturePaymaster.acceptOwnership();

        // it should transfer ownership
        assertEq(s_signaturePaymaster.owner(), s_account3);
    }
}

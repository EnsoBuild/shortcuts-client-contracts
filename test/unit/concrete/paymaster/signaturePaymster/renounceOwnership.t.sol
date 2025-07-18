// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_RenounceOwnership_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.renounceOwnership();
    }

    function test_WhenCallerIsOwner() external {
        vm.prank(s_owner);
        s_signaturePaymaster.renounceOwnership();

        // it should transfer ownership to zero address
        assertEq(s_signaturePaymaster.owner(), address(0));
    }
}

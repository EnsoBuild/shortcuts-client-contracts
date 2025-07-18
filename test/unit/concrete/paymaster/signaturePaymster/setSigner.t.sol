// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_SetSigner_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.setSigner(address(777), true);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_SignerIsAlreadySet() external whenCallerIsOwner {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(SignaturePaymaster.SignerIsAlreadySet.selector, address(0), false));
        s_signaturePaymaster.setSigner(address(0), false);
    }

    function test_WhenSignerIsNotSet() external whenCallerIsOwner {
        // it should emit SignerAdded event
        vm.expectEmit(address(s_signaturePaymaster));
        emit SignaturePaymaster.SignerSet(s_account3, true);
        s_signaturePaymaster.setSigner(s_account3, true);

        // it should map isValid
        assertEq(s_signaturePaymaster.validSigners(s_account3), true);
    }
}

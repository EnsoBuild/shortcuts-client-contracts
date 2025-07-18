// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_WithdrawTo_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    uint256 private s_depositAmount;

    function setUp() public virtual override {
        super.setUp();

        s_depositAmount = 0.777 ether;

        vm.prank(s_account4);
        s_signaturePaymaster.deposit{ value: s_depositAmount }();
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.withdrawTo(s_account3, s_depositAmount - 1);
    }

    function test_WhenCallerIsOwner() external {
        uint256 withdrawAmount = s_depositAmount - 1;
        uint256 balancePre = s_account3.balance;

        // it should withdraw amount
        vm.prank(s_owner);
        s_signaturePaymaster.withdrawTo(s_account3, withdrawAmount);

        uint256 balancePost = s_account3.balance;
        assertEq(balancePost - balancePre, withdrawAmount);
    }
}

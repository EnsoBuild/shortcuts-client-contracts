// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { console2 } from "forge-std/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_WithdrawStake_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    uint256 private s_stakeAmount;

    function setUp() public virtual override {
        super.setUp();

        s_stakeAmount = 0.777 ether;
        uint32 stakeDelay = 1;

        vm.startPrank(s_owner);
        s_signaturePaymaster.addStake{ value: s_stakeAmount }(stakeDelay);
        s_signaturePaymaster.unlockStake();
        vm.stopPrank();

        vm.warp(stakeDelay + 1);
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.withdrawStake(s_account3);
    }

    function test_WhenCallerIsOwner() external {
        uint256 balancePre = s_account3.balance;

        // it should withdraw all stake
        vm.prank(s_owner);
        s_signaturePaymaster.withdrawStake(s_account3);

        uint256 balancePost = s_account3.balance;
        assertEq(balancePost - balancePre, s_stakeAmount);
    }
}

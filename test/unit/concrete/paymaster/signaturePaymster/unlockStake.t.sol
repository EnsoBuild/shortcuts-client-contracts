// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";
import { IStakeManager } from "account-abstraction-v7/interfaces/IStakeManager.sol";

import { console2 } from "forge-std/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_UnlockStake_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    uint32 private s_stakeDelay;

    function setUp() public virtual override {
        super.setUp();

        s_stakeDelay = 1;
        vm.prank(s_owner);
        s_signaturePaymaster.addStake{ value: 0.777 ether }(s_stakeDelay);
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.unlockStake();
    }

    function test_WhenCallerIsOwner() external {
        // IStakeManager.DepositInfo memory depositInfo = s_entryPoint.getDepositInfo(address(s_signaturePaymaster));
        // vm.warp(blockdepositInfo.withdrawTime);

        // it should unlock stake
        vm.expectEmit(address(s_entryPoint));
        emit IStakeManager.StakeUnlocked(address(s_signaturePaymaster), s_stakeDelay + 1);
        vm.prank(s_owner);
        s_signaturePaymaster.unlockStake();
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";
import { IStakeManager } from "account-abstraction-v7/interfaces/IStakeManager.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_AddStake_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.addStake(uint32(10));
    }

    function test_WhenCallerIsOwner() external {
        uint256 stakeAmount = 0.777 ether;
        IStakeManager.DepositInfo memory depositInfoPre = s_entryPoint.getDepositInfo(address(s_signaturePaymaster));

        vm.prank(s_owner);
        s_signaturePaymaster.addStake{ value: stakeAmount }(uint32(10));

        // it should increase stake balance
        IStakeManager.DepositInfo memory depositInfoAfter = s_entryPoint.getDepositInfo(address(s_signaturePaymaster));

        assertEq(depositInfoAfter.stake - depositInfoPre.stake, stakeAmount);
    }
}

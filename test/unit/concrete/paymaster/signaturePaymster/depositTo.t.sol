// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";
import { IStakeManager } from "account-abstraction-v7/interfaces/IStakeManager.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract SignaturePaymaster_DepositTo_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_ShouldIncrementDeposit() external {
        uint256 depositAmount = 0.777 ether;
        IStakeManager.DepositInfo memory depositInfoPre = s_entryPoint.getDepositInfo(address(s_signaturePaymaster));

        vm.prank(s_account4);
        s_signaturePaymaster.deposit{ value: depositAmount }();

        // it should increment deposit
        IStakeManager.DepositInfo memory depositInfoAfter = s_entryPoint.getDepositInfo(address(s_signaturePaymaster));

        assertEq(depositInfoAfter.deposit - depositInfoPre.deposit, depositAmount);
    }
}

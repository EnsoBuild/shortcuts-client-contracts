// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";

import { Vm, console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";

contract SignaturePaymaster_PostOp_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_RevertWhen_CallerIsNotEntryPoint() external {
        IPaymaster.PostOpMode postOpMode = IPaymaster.PostOpMode.opSucceeded;
        bytes memory context;
        uint256 actualGasCost = 0;
        uint256 actualUserOpFeePerGas = 0;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(SignaturePaymaster.InvalidEntryPoint.selector, s_owner));
        vm.prank(s_owner);
        s_signaturePaymaster.postOp(postOpMode, context, actualGasCost, actualUserOpFeePerGas);
    }

    function test_WhenCallerIsEntryPoint() external {
        IPaymaster.PostOpMode postOpMode = IPaymaster.PostOpMode.opSucceeded;
        bytes memory context;
        uint256 actualGasCost = 0;
        uint256 actualUserOpFeePerGas = 0;

        bytes memory encodedCall =
            abi.encodeCall(SignaturePaymaster.postOp, (postOpMode, context, actualGasCost, actualUserOpFeePerGas));

        vm.prank(address(s_entryPoint));
        vm.recordLogs();
        vm.startStateDiffRecording();

        uint256 gasPre = gasleft();
        (bool success, bytes memory result) = address(s_signaturePaymaster).call(encodedCall);
        // s_signaturePaymaster.postOp(postOpMode, context, actualGasCost, actualUserOpFeePerGas);
        uint256 gasPost = gasleft();

        Vm.AccountAccess[] memory records = vm.stopAndReturnStateDiff();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // it should noop
        (success);
        assertEq(result, "");
        assertEq(gasPre - gasPost, 5432);
        assertEq(records.length, 1);
        assertEq(records[0].storageAccesses.length, 1); // NOTE: `onlyEntryPoint` modifier accesses `entryPoint`
        assertEq(records[0].storageAccesses[0].isWrite, false);
        assertEq(entries.length, 0);
    }
}

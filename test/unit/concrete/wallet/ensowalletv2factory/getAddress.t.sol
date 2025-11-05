// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2Factory } from "../../../../../src/wallet/EnsoWalletV2Factory.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "../ensowalletv2/EnsoWalletV2.t.sol";
import { Vm } from "forge-std/Test.sol";

contract EnsoWalletV2Factory_GetAddress_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    function test_WhenCalled() external {
        // it should return predicted address
        address predictedAddress = s_walletFactory.getAddress(s_account1);

        // it should be correct (not deployed yet, but predictable)
        assertTrue(predictedAddress != address(0));
        assertTrue(predictedAddress.code.length == 0);

        // Deploy to verify
        vm.startPrank(s_user);
        address actualAddress = s_walletFactory.deploy(s_account1);

        assertEq(predictedAddress, actualAddress);
    }

    function test_WhenCalledMultipleTimes() external {
        // it should return same address for same account
        address predictedAddress1 = s_walletFactory.getAddress(s_account1);
        address predictedAddress2 = s_walletFactory.getAddress(s_account1);

        assertEq(predictedAddress1, predictedAddress2);
    }

    function test_WhenDifferentAccounts() external {
        // it should return different addresses for different accounts
        address predictedAddress1 = s_walletFactory.getAddress(s_account1);
        address predictedAddress2 = s_walletFactory.getAddress(s_account2);

        assertTrue(predictedAddress1 != predictedAddress2);
    }

    function test_WhenDeployedTwice() external {
        // it should emit event only on first deployment
        address predictedAddress = s_walletFactory.getAddress(s_account1);

        vm.startPrank(s_user);

        // First deployment - should emit event
        vm.expectEmit(true, true, true, true, address(s_walletFactory));
        emit EnsoWalletV2Factory.EnsoWalletV2Deployed(predictedAddress, s_account1);
        address walletAddress1 = s_walletFactory.deploy(s_account1);

        // Second deployment - should not emit event (same address)
        vm.recordLogs();
        address walletAddress2 = s_walletFactory.deploy(s_account1);

        // Verify same address returned
        assertEq(walletAddress1, walletAddress2);
        assertEq(walletAddress1, predictedAddress);

        // Verify no events were emitted on second deployment
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }
}


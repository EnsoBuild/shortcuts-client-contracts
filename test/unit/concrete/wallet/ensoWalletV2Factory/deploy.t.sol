// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2Factory } from "../../../../../src/wallet/EnsoWalletV2Factory.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "../ensoWalletV2/EnsoWalletV2.t.sol";

contract EnsoWalletV2Factory_Deploy_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    function test_WhenCalled() external {
        // it should deploy new wallet
        vm.startPrank(s_user);
        address walletAddress = s_walletFactory.deploy(s_account1);

        // it should be a contract
        assertTrue(walletAddress.code.length > 0);

        // it should be correctly initialized
        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        assertEq(wallet.owner(), s_account1);
        assertEq(wallet.factory(), address(s_walletFactory));
    }

    function test_WhenCalledMultipleTimes() external {
        // it should return same address for same account
        vm.startPrank(s_user);
        address walletAddress1 = s_walletFactory.deploy(s_account1);
        address walletAddress2 = s_walletFactory.deploy(s_account1);

        assertEq(walletAddress1, walletAddress2);
    }

    function test_WhenDifferentAccounts() external {
        // it should return different addresses for different accounts
        vm.startPrank(s_user);
        address walletAddress1 = s_walletFactory.deploy(s_account1);
        address walletAddress2 = s_walletFactory.deploy(s_account2);

        assertTrue(walletAddress1 != walletAddress2);
    }
}

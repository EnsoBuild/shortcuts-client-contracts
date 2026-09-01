// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { KeeperWallet } from "../../../../../src/wallet/KeeperWallet.sol";
import { KeeperWallet_Unit_Concrete_Test, Target } from "./KeeperWallet.t.sol";

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract KeeperWallet_SetExecutor_Unit_Concrete_Test is KeeperWallet_Unit_Concrete_Test {
    function test_WhenOwnerAddsExecutor() external {
        // it should allow the account to execute and emit ExecutorSet
        vm.prank(s_owner);
        vm.expectEmit(address(s_wallet));
        emit KeeperWallet.ExecutorSet(s_user, true);
        s_wallet.setExecutor(s_user, true);

        assertTrue(s_wallet.executors(s_user));

        vm.prank(s_user);
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.func, ()));
    }

    function test_WhenOwnerRemovesExecutor() external {
        // it should revoke execution rights and emit ExecutorSet
        vm.prank(s_owner);
        vm.expectEmit(address(s_wallet));
        emit KeeperWallet.ExecutorSet(s_executor, false);
        s_wallet.setExecutor(s_executor, false);

        assertFalse(s_wallet.executors(s_executor));

        vm.prank(s_executor);
        vm.expectRevert(abi.encodeWithSelector(KeeperWallet.KeeperWallet_InvalidSender.selector, s_executor));
        s_wallet.execute(address(s_target), 0, "");
    }

    function test_RevertWhen_CallerNotOwner() external {
        // it should revert even for an executor
        vm.prank(s_executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_executor));
        s_wallet.setExecutor(s_user, true);
    }
}

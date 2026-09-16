// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { KeeperWallet } from "../../../../../src/wallet/KeeperWallet.sol";
import { KeeperWallet_Unit_Concrete_Test, Target } from "./KeeperWallet.t.sol";

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract KeeperWallet_Ownership_Unit_Concrete_Test is KeeperWallet_Unit_Concrete_Test {
    function test_WhenOwnershipTransferCompletes() external {
        // it should transfer ownership in two steps and move execution rights to the new owner
        vm.prank(s_owner);
        s_wallet.transferOwnership(s_user);

        assertEq(s_wallet.owner(), s_owner);
        assertEq(s_wallet.pendingOwner(), s_user);

        vm.prank(s_user);
        s_wallet.acceptOwnership();

        assertEq(s_wallet.owner(), s_user);
        assertEq(s_wallet.pendingOwner(), address(0));

        vm.prank(s_user);
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.func, ()));

        vm.prank(s_owner);
        vm.expectRevert(abi.encodeWithSelector(KeeperWallet.KeeperWallet_InvalidSender.selector, s_owner));
        s_wallet.execute(address(s_target), 0, "");
    }

    function test_WhenOwnershipTransferPending() external {
        // it should keep executors valid while the transfer is pending
        vm.prank(s_owner);
        s_wallet.transferOwnership(s_user);

        vm.prank(s_executor);
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.func, ()));
    }

    function test_RevertWhen_PendingOwnerExecutesBeforeAccept() external {
        // it should not grant execution rights until the transfer is accepted
        vm.prank(s_owner);
        s_wallet.transferOwnership(s_user);

        vm.prank(s_user);
        vm.expectRevert(abi.encodeWithSelector(KeeperWallet.KeeperWallet_InvalidSender.selector, s_user));
        s_wallet.execute(address(s_target), 0, "");
    }

    function test_RevertWhen_NonPendingOwnerAccepts() external {
        // it should revert
        vm.prank(s_owner);
        s_wallet.transferOwnership(s_user);

        vm.prank(s_executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_executor));
        s_wallet.acceptOwnership();
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { KeeperWallet } from "../../../../../src/wallet/KeeperWallet.sol";
import { KeeperWallet_Unit_Concrete_Test, Target } from "./KeeperWallet.t.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract KeeperWallet_Execute_Unit_Concrete_Test is KeeperWallet_Unit_Concrete_Test {
    function test_WhenCallerIsOwner() external {
        // it should execute the call and return the response
        vm.prank(s_owner);
        bytes memory response = s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.func, ()));

        assertEq(abi.decode(response, (uint256)), 42);
    }

    function test_WhenCallerIsExecutor() external {
        // it should execute the call and return the response
        vm.prank(s_executor);
        bytes memory response = s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.func, ()));

        assertEq(abi.decode(response, (uint256)), 42);
    }

    function test_WhenCallHasValue() external {
        // it should forward the value to the target
        uint256 value = 1 ether;

        vm.prank(s_owner);
        bytes memory response =
            s_wallet.execute{ value: value }(address(s_target), value, abi.encodeCall(Target.funcWithValue, ()));

        assertEq(abi.decode(response, (uint256)), value);
        assertEq(address(s_target).balance, value);
    }

    function test_WhenOwnerWithdrawsWalletFunds() external {
        // it should let the owner move native and ERC20 balances out of the wallet
        vm.prank(s_user);
        (bool sent,) = address(s_wallet).call{ value: 2 ether }("");
        assertTrue(sent);
        s_erc20.mint(address(s_wallet), 100e18);

        uint256 ownerBalanceBefore = s_owner.balance;

        vm.startPrank(s_owner);
        s_wallet.execute(s_owner, 2 ether, "");
        s_wallet.execute(address(s_erc20), 0, abi.encodeCall(IERC20.transfer, (s_owner, 100e18)));
        vm.stopPrank();

        assertEq(s_owner.balance, ownerBalanceBefore + 2 ether);
        assertEq(address(s_wallet).balance, 0);
        assertEq(s_erc20.balanceOf(s_owner), 100e18);
    }

    function test_RevertWhen_TargetRevertsString() external {
        // it should bubble up the revert reason
        vm.prank(s_owner);
        vm.expectRevert(bytes("Test revert"));
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.revertString, ()));
    }

    function test_RevertWhen_TargetRevertsCustomError() external {
        // it should bubble up the custom error
        vm.prank(s_owner);
        vm.expectRevert(Target.Target_Revert.selector);
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.revertCustomError, ()));
    }

    function test_RevertWhen_TargetRevertsNoReason() external {
        // it should revert with ExecutionFailedNoReason
        vm.prank(s_owner);
        vm.expectRevert(KeeperWallet.KeeperWallet_ExecutionFailedNoReason.selector);
        s_wallet.execute(address(s_target), 0, abi.encodeCall(Target.revertNoReason, ()));
    }

    function test_RevertWhen_CallerNotAuthorized() external {
        // it should revert when caller is neither owner nor executor
        vm.prank(s_user);
        vm.expectRevert(abi.encodeWithSelector(KeeperWallet.KeeperWallet_InvalidSender.selector, s_user));
        s_wallet.execute(address(s_target), 0, "");
    }
}

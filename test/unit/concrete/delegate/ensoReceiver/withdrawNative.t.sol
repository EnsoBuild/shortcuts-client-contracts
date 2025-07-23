// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { Withdrawable } from "../../../../../src/utils/Withdrawable.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract EnsoReceiver_WithdrawNative_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    function test_RevertWhen_CallerIsNotOwner() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.withdrawNative(777);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_CallIsNotSuccessful() external whenCallerIsOwner {
        uint256 amount = 1 ether;
        vm.deal(address(s_ensoReceiver), amount);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Withdrawable.WithdrawFailed.selector));
        s_ensoReceiver.withdrawNative(amount - 1);
    }

    function test_WhenCallIsSuccessful() external whenCallerIsOwner {
        uint256 amount = 1 ether;
        vm.deal(address(s_ensoReceiver), amount);

        // Get balances before withdrawal
        uint256 ensoReceiverBalancePre = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ownerBalancePre = balance(NATIVE_ASSET, address(s_owner));

        s_ensoReceiver.withdrawNative(amount);

        // Get balances after withdrawal
        uint256 ensoReceiverBalancePost = balance(NATIVE_ASSET, address(s_ensoReceiver));
        uint256 ownerBalancePost = balance(NATIVE_ASSET, address(s_owner));

        // it should send native token amount to owner
        assertBalanceDiff(ensoReceiverBalancePre, ensoReceiverBalancePost, -int256(amount), "EnsoReceiver NATIVE ASSET");
        assertBalanceDiff(ownerBalancePre, ownerBalancePost, int256(amount), "Owner NATIVE ASSET");
    }
}

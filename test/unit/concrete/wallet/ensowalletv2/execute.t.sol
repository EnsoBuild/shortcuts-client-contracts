// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "./EnsoWalletV2.t.sol";

contract Target {
    function func() external pure returns (uint256) {
        return 42;
    }

    function functionWithValue(uint256 value) external payable returns (uint256) {
        return value;
    }

    function revert() external pure {
        revert("Test revert");
    }
}

contract EnsoWalletV2_Execute_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    Target internal s_target;

    function setUp() public override {
        super.setUp();

        s_target = new Target();
        vm.label(address(s_target), "Target");

        s_wallet = _deployWallet(s_owner);
    }

    function test_WhenValidCall() external {
        // it should execute call successfully
        vm.startPrank(s_owner);
        bool success = s_wallet.execute(address(s_target), 0, abi.encodeWithSelector(Target.func.selector));

        assertTrue(success);
    }

    function test_WhenCallWithValue() external {
        // it should execute call with value
        uint256 value = 1 ether;

        vm.startPrank(s_owner);
        bool success = s_wallet.execute{ value: value }(
            address(s_target), value, abi.encodeWithSelector(Target.functionWithValue.selector, value)
        );

        assertTrue(success);
    }

    function test_RevertWhen_TargetReverts() external {
        // it should revert when target call reverts
        vm.startPrank(s_owner);
        bool success = s_wallet.execute(address(s_target), 0, abi.encodeWithSelector(Target.revert.selector));

        assertFalse(success);
    }

    function test_RevertWhen_NotOwner() external {
        // it should revert when not called by owner
        vm.startPrank(s_user);
        vm.expectRevert(abi.encodeWithSelector(EnsoWalletV2.InvalidSender.selector, s_user));
        s_wallet.execute(address(s_target), 0, "");
    }
}


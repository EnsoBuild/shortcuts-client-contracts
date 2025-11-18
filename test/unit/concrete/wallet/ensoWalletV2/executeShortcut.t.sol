// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { IEnsoWalletV2 } from "../../../../../src/wallet/interfaces/IEnsoWalletV2.sol";
import { WeirollPlanner } from "../../../../utils/WeirollPlanner.sol";

import { EnsoWalletV2_Unit_Concrete_Test } from "./EnsoWalletV2.t.sol";
import { WETH } from "solady/tokens/WETH.sol";

contract Target {
    function func() external payable returns (uint256) {
        return 42;
    }

    function revertFunc() external pure {
        revert("Test revert");
    }
}

contract EnsoWalletV2_ExecuteShortcut_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    bytes32 internal constant ACCOUNT_ID = bytes32("test_account");
    bytes32 internal constant REQUEST_ID = bytes32("test_request");
    WETH internal weth;

    function setUp() public override {
        super.setUp();
        s_wallet = _deployWallet(s_owner);
        weth = new WETH();
    }

    function test_WhenCalledByOwner() external {
        // it should allow owner to execute shortcuts
        vm.startPrank(s_owner);
        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        s_wallet.executeShortcut(ACCOUNT_ID, REQUEST_ID, commands, state);
    }

    function test_WhenCalledByFactory() external {
        // it should allow factory to execute shortcuts
        vm.startPrank(address(s_walletFactory));
        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        s_wallet.executeShortcut(ACCOUNT_ID, REQUEST_ID, commands, state);
    }

    function test_RevertWhen_NotOwnerOrFactory() external {
        // it should revert when not called by owner or factory
        vm.startPrank(s_user);
        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IEnsoWalletV2.EnsoWalletV2_InvalidSender.selector, s_user));
        s_wallet.executeShortcut(ACCOUNT_ID, REQUEST_ID, commands, state);
    }

    function test_executeShortcutWithNative() external {
        // action:
        // wrap 1 ETH to WETH
        // transfer 1 WETH to s_account1

        uint256 value = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        commands[1] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0100ffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(1 ether);
        state[1] = abi.encode(s_account1);

        vm.startPrank(s_owner);
        vm.deal(address(s_wallet), value);

        s_wallet.executeShortcut{ value: value }(ACCOUNT_ID, REQUEST_ID, commands, state);

        // it should transfer WETH to account1
        assertEq(weth.balanceOf(s_account1), value);
    }

    function test_executeShortcutWithERC20() external {
        // action:
        // transfer 1 WETH to s_account1

        uint256 value = 1 ether;

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0001ffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(s_account1);
        state[1] = abi.encode(value);

        vm.startPrank(s_owner);

        // fund wallet with WETH
        weth.deposit{ value: value }();
        weth.transfer(address(s_wallet), value);

        s_wallet.executeShortcut(ACCOUNT_ID, REQUEST_ID, commands, state);

        // it should transfer WETH to account1
        assertEq(weth.balanceOf(s_account1), value);
    }

    function test_revert_executeShortcut() external {
        // action:
        // wrap 1 ETH to WETH
        // but try to wrap more than available

        uint256 value = 1 ether;

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        // should revert because not enough ETH
        state[0] = abi.encode(value + 1);

        vm.startPrank(s_owner);

        vm.expectRevert();
        s_wallet.executeShortcut{ value: value }(ACCOUNT_ID, REQUEST_ID, commands, state);
    }

    function test_WhenWithValue() external {
        // it should handle value transfers
        uint256 value = 0.5 ether;

        vm.deal(address(s_wallet), value);
        vm.startPrank(s_owner);

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        uint256 balanceBefore = address(s_wallet).balance;
        s_wallet.executeShortcut{ value: value }(ACCOUNT_ID, REQUEST_ID, commands, state);
        uint256 balanceAfter = address(s_wallet).balance;

        // Value should be transferred to the wallet
        assertEq(balanceAfter - balanceBefore, value);
    }
}

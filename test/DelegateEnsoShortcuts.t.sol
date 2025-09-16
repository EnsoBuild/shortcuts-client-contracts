// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { DelegateDeployer, DelegateDeployerResult } from "../script/DelegateDeployer.s.sol";
import { AbstractEnsoShortcuts, DelegateEnsoShortcuts } from "../src/delegate/DelegateEnsoShortcuts.sol";
import { WeirollPlanner } from "./utils/WeirollPlanner.sol";
import { Test } from "forge-std/Test.sol";
import { Enum, SafeInstance, SafeTestLib, SafeTestTools } from "safe-tools/SafeTestTools.sol";
import { WETH } from "solady/tokens/WETH.sol";

contract DelegateEnsoShortcutsTest is Test, SafeTestTools {
    using SafeTestLib for SafeInstance;

    DelegateEnsoShortcuts shortcuts;
    SafeInstance safeInstance;
    WETH weth;

    address alice = makeAddr("alice");

    function setUp() public {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        deal(deployer, 1 ether);

        DelegateDeployerResult memory result = new DelegateDeployer().run();

        shortcuts = result.delegate;

        safeInstance = _setupSafe();

        weth = new WETH();
    }

    function testSafeCanRunShortcutTransferringERC20() public {
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(weth)
        );

        bytes[] memory state = new bytes[](2);
        state[0] = abi.encode(alice);
        state[1] = abi.encode(10 ether);

        bytes memory data =
            abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));

        assertEq(weth.balanceOf(address(safeInstance.safe)), 0);
        assertEq(weth.balanceOf(alice), 0);

        deal(address(weth), address(safeInstance.safe), 10 ether);

        assertEq(weth.balanceOf(address(safeInstance.safe)), 10 ether);
        assertEq(weth.balanceOf(alice), 0);

        safeInstance.execTransaction({
            to: address(shortcuts),
            value: 0 ether,
            data: data,
            operation: Enum.Operation.DelegateCall
        });

        assertEq(weth.balanceOf(address(safeInstance.safe)), 0);
        assertEq(weth.balanceOf(alice), 10 ether);
    }

    function testSafeCanRunShortcutDepositingEther() public {
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        bytes[] memory state = new bytes[](1);
        state[0] = abi.encode(10 ether);

        bytes memory data =
            abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));

        uint256 safeBalanceBefore = address(safeInstance.safe).balance;
        assertEq(weth.balanceOf(address(safeInstance.safe)), 0);

        safeInstance.execTransaction({
            to: address(shortcuts),
            value: 0 ether,
            data: data,
            operation: Enum.Operation.DelegateCall
        });

        assertEq(weth.balanceOf(address(safeInstance.safe)), 10 ether);
        assertEq(safeBalanceBefore - 10 ether, address(safeInstance.safe).balance);
    }

    function testToDirectlyCallDelegateContract() public {
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        bytes[] memory state = new bytes[](1);
        state[0] = abi.encode(10 ether);

        vm.expectRevert(DelegateEnsoShortcuts.OnlyDelegateCall.selector);
        shortcuts.executeShortcut(bytes32(0), bytes32(0), commands, state);
    }
}

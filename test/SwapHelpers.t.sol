// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../lib/forge-std/src/Test.sol";

import "../src/helpers/SwapHelpers.sol";
import "../src/EnsoShortcuts.sol";
import "../src/router/EnsoRouter.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockVault.sol";

import "./utils/WeirollPlanner.sol";

contract SwapHelpersTest is Test {
    SwapHelpers public swapHelpers;
    EnsoRouter public router;
    EnsoShortcuts public shortcuts;
    MockERC20 public token;
    MockVault public vault;

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    uint256 public constant AMOUNT = 10 ** 18;
    uint256 public constant MAX_AMOUNT_OUT = AMOUNT/2;
    uint256 public constant TOKENID = 1;
    address public constant FEE_RECEIVER = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        swapHelpers = new SwapHelpers();
        router = new EnsoRouter();
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
        token = new MockERC20("Test", "TST");
        vault = new MockVault("Vault", "VLT", address(token));
        token.mint(address(this), AMOUNT * 10);
    }

    function testSwap() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(swapHelpers), AMOUNT);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(swapHelpers));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC20, abi.encode(address(vault), MAX_AMOUNT_OUT));

        bytes memory swapData =
            abi.encodeWithSelector(router.safeRouteSingle.selector, tokenIn, tokenOut, address(swapHelpers), data);

        swapHelpers.swap(address(router), token, vault, AMOUNT, address(this), swapData, new uint256[](0));

        assertEq(AMOUNT, vault.balanceOf(address(this)));
    }

    function testSwapWithLimit() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(swapHelpers), AMOUNT);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(swapHelpers));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC20, abi.encode(address(vault), MAX_AMOUNT_OUT));

        bytes memory swapData =
            abi.encodeWithSelector(router.safeRouteSingle.selector, tokenIn, tokenOut, address(swapHelpers), data);

        swapHelpers.swapWithLimit(address(router), address(router), token, vault, AMOUNT, MAX_AMOUNT_OUT, address(this), FEE_RECEIVER, swapData, new uint256[](0));

        assertEq(AMOUNT - MAX_AMOUNT_OUT, vault.balanceOf(address(this)));
        assertEq(MAX_AMOUNT_OUT, vault.balanceOf(FEE_RECEIVER));
    }
}

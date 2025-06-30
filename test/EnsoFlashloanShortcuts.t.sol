// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../lib/forge-std/src/Test.sol";

import "../src/flashloan/EnsoFlashloanShortcuts.sol";
import "../src/router/EnsoRouter.sol";

import "./mocks/MockERC1155.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";

import "./mocks/MockMultiVault.sol";
import "./mocks/MockNFTVault.sol";
import "./mocks/MockVault.sol";

import "./utils/WeirollPlanner.sol";

import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}

contract EnsoFlashloanShortcutsTest is Test, ERC721Holder, ERC1155Holder {
    EnsoFlashloanShortcuts public shortcuts;

    address user_bob = makeAddr("bob");
    address receiver = makeAddr("receiver");

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        shortcuts = new EnsoFlashloanShortcuts(
            IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb),
            IEulerGenericFactory(0x29a56a1b8214D9Cf7c5561811750D5cBDb45CC8e)
        );
    }

    // Morpho test:
    // - flashlent asset: WETH
    // - no other assets involved
    // - WETH.withdraw -> WETH.deposit
    function testMorphoFlashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
        uint256 amount = 10 ** 18;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);

        bytes memory morphoData = abi.encode(token, amount);

        shortcuts.flashLoan(
            FlashloanProtocols.Morpho,
            user_bob,
            morphoData,
            commands,
            state
        );
    }

    // Morpho test:
    // - flashlent asset: WETH
    // - other assets: additional WETH
    // - WETH.withdraw -> WETH.deposit
    // - make sure excess is sent back to user
    function testMorphoFlashloan_excess() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
        uint256 amount = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);

        bytes memory morphoData = abi.encode(token, amount);

        vm.startPrank(user_bob);
        vm.deal(user_bob, amount);
        token.deposit{value: amount}();

        // Simulate that router transfers tokens to flashloan contract
        token.transfer(address(shortcuts), amount);

        uint256 balanceBefore = token.balanceOf(receiver);
        shortcuts.flashLoan(
            FlashloanProtocols.Morpho,
            receiver,
            morphoData,
            commands,
            state
        );
        uint256 balanceAfter = token.balanceOf(receiver);

        assertEq(balanceAfter - balanceBefore, amount);
    }

    // Euler test:
    // - flashlent asset: WETH
    // - no other assets involved
    // - WETH.withdraw -> WETH.deposit
    function testEulerFlashLoan() public {
        vm.selectFork(_ethereumFork);

        // eWETH-2 Euler vault
        address eulerVault = address(
            0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2
        );

        IWETH token = IWETH(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
        uint256 amount = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);

        bytes memory eulerData = abi.encode(token, amount, eulerVault);

        shortcuts.flashLoan(
            FlashloanProtocols.Euler,
            user_bob,
            eulerData,
            commands,
            state
        );
    }

    // Euler test:
    // - flashlent asset: WETH
    // - other assets: additional WETH
    // - WETH.withdraw -> WETH.deposit
    // - make sure excess is sent back to user
    function testEulerFlashLoan_excess() public {
        vm.selectFork(_ethereumFork);

        // eWETH-2 Euler vault
        address eulerVault = address(
            0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2
        );

        IWETH token = IWETH(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
        uint256 amount = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);

        bytes memory eulerData = abi.encode(token, amount, eulerVault);

        vm.startPrank(user_bob);
        vm.deal(user_bob, amount);
        token.deposit{value: amount}();

        // Simulate that router transfers tokens to flashloan contract
        token.transfer(address(shortcuts), amount);

        uint256 balanceBefore = token.balanceOf(receiver);
        shortcuts.flashLoan(
            FlashloanProtocols.Euler,
            receiver,
            eulerData,
            commands,
            state
        );

        uint256 balanceAfter = token.balanceOf(receiver);

        assertEq(balanceAfter - balanceBefore, amount);
    }

    // Euler test:
    // - revert if attacker calls onFlashLoan with fake Euler vault
    function testEulerFlashLoan_fakeEulerVault() public {
        vm.selectFork(_ethereumFork);

        address fakeEulerVault = address(0xdead);

        bytes memory data = bytes("");

        vm.prank(fakeEulerVault);
        vm.expectRevert(EnsoFlashloanShortcuts.NotAuthorized.selector);
        shortcuts.onFlashLoan(data);
    }
}

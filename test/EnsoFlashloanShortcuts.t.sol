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
            address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb) // Morpho
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

        shortcuts.flashLoan(
            FlashloanProtocols.Morpho,
            address(token),
            amount,
            user_bob,
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
        uint256 amount = 10 ** 18;

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

        vm.startPrank(user_bob);
        vm.deal(user_bob, 1 ether);
        token.deposit{value: 1 ether}();

        // Simulate that router transfers tokens to flashloan contract
        token.transfer(address(shortcuts), 1 ether);

        uint256 balanceBefore = token.balanceOf(receiver);
        shortcuts.flashLoan(
            FlashloanProtocols.Morpho,
            address(token),
            amount,
            receiver,
            commands,
            state
        );
        uint256 balanceAfter = token.balanceOf(receiver);

        // Check that receiver received the excess WETH
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }
}

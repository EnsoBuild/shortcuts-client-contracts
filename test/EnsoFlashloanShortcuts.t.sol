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

    address morpho = address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        shortcuts = new EnsoFlashloanShortcuts();
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

        bytes memory morphoData = abi.encode(morpho, token, amount);

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

        bytes memory morphoData = abi.encode(morpho, token, amount);

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

    // BalancerV2 test:
    // - flashlent asset: WETH
    // - no other assets involved
    // - WETH.withdraw -> WETH.deposit
    function testBalancerV2Flashloan() public {
        vm.selectFork(_ethereumFork);

        address balancerV2Vault = address(
            0xBA12222222228d8Ba445958a75a0704d566BF2C8
        );

        IWETH weth = IWETH(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        uint256 wethAmount = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            weth.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );
        commands[1] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(wethAmount);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(weth);
        amounts[0] = wethAmount;

        bytes memory balancerV2Data = abi.encode(
            balancerV2Vault,
            tokens,
            amounts
        );

        shortcuts.flashLoan(
            FlashloanProtocols.BalancerV2,
            user_bob,
            balancerV2Data,
            commands,
            state
        );
    }

    // BalancerV2 test:
    // - flashlent assets: WETH and USDC
    // - no other assets involved
    // - WETH.withdraw -> WETH.deposit
    function testBalancerV2Flashloan_multipleAssets() public {
        vm.selectFork(_ethereumFork);

        address balancerV2Vault = address(
            0xBA12222222228d8Ba445958a75a0704d566BF2C8
        );

        IWETH weth = IWETH(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        uint256 wethAmount = 1 ether;

        address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 usdcAmount = 100 * 10 ** 6;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            weth.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );
        commands[1] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(wethAmount);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        // NOTE: Tokens must be in sorted order
        tokens[0] = address(usdc);
        amounts[0] = usdcAmount;
        tokens[1] = address(weth);
        amounts[1] = wethAmount;

        bytes memory balancerV2Data = abi.encode(
            balancerV2Vault,
            tokens,
            amounts
        );

        shortcuts.flashLoan(
            FlashloanProtocols.BalancerV2,
            user_bob,
            balancerV2Data,
            commands,
            state
        );
    }

    function testBalancerV2Flashloan_excess() public {
        vm.selectFork(_ethereumFork);

        address balancerV2Vault = address(
            0xBA12222222228d8Ba445958a75a0704d566BF2C8
        );

        IWETH weth = IWETH(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        uint256 wethAmount = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](1);

        // Unwrap -> Wrap
        commands[0] = WeirollPlanner.buildCommand(
            weth.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );
        commands[1] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call
            0x00ffffffffff, // 1 inputs
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(wethAmount);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = address(weth);
        amounts[0] = wethAmount;

        bytes memory balancerV2Data = abi.encode(
            balancerV2Vault,
            tokens,
            amounts
        );

        vm.startPrank(user_bob);
        vm.deal(user_bob, wethAmount);
        weth.deposit{value: wethAmount}();

        // Simulate that router transfers tokens to flashloan contract
        weth.transfer(address(shortcuts), wethAmount);

        uint256 balanceBefore = weth.balanceOf(receiver);
        shortcuts.flashLoan(
            FlashloanProtocols.BalancerV2,
            receiver,
            balancerV2Data,
            commands,
            state
        );
        uint256 balanceAfter = weth.balanceOf(receiver);

        assertEq(balanceAfter - balanceBefore, wethAmount);
    }

    function testAaveV3FlashLoan() public {
        vm.selectFork(_ethereumFork);

        IAaveV3Pool aaveV3Pool = IAaveV3Pool(
            address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2)
        );
        IWETH token = IWETH(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );

        uint256 amount = 1 ether;
        uint256 BPS = 10_000;
        uint256 totalFee = aaveV3Pool.FLASHLOAN_PREMIUM_TOTAL();
        uint256 fee = (amount * totalFee) / BPS;

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
        bytes memory aaveData = abi.encode(aaveV3Pool, token, amount);

        // Pretend that user did necessary actions to have enough to repay
        // for the flashloan with fee
        vm.startPrank(user_bob);
        vm.deal(user_bob, amount);
        token.deposit{value: fee}();
        token.transfer(address(shortcuts), fee);

        shortcuts.flashLoan(
            FlashloanProtocols.AaveV3,
            user_bob,
            aaveData,
            commands,
            state
        );
    }
}

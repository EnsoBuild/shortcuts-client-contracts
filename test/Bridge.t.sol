// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../src/EnsoShortcuts.sol";
import { LayerZeroReceiver } from "../src/bridge/LayerZeroReceiver.sol";
import { EnsoRouter } from "../src/router/EnsoRouter.sol";
import { WeirollPlanner } from "./utils/WeirollPlanner.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { Test } from "forge-std/Test.sol";

import { console } from "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external;
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external;
    function balanceOf(address owner) external view returns (uint256);
}

contract BridgeTest is Test {
    LayerZeroReceiver public lzReceiver;
    EnsoRouter public router;
    EnsoShortcuts public shortcuts;
    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public eth = address(0);
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public ethPool = 0x77b2043768d28E9C9aB44E1aBfC95944bcE57931;
    address public usdcPool = 0xc026395860Db2d07ee33e05fE50ed7bD583189C7;
    address public vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    uint256 public constant ETH_AMOUNT = 10 ** 18;
    uint256 public constant USDC_AMOUNT = 10 ** 9;

    error TransferFailed();

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        router = new EnsoRouter();
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
        lzReceiver = new LayerZeroReceiver(address(this), address(router), address(this), 100_000);

        address[] memory ofts = new address[](2);
        ofts[0] = ethPool;
        ofts[1] = usdcPool;
        lzReceiver.setOFTs(ofts);
    }

    function testEthBridge() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = weth.balanceOf(address(this));

        (bytes32[] memory commands, bytes[] memory state) = _buildWethDeposit(ETH_AMOUNT);
        bytes memory message = _buildLzComposeMessage(ETH_AMOUNT, commands, state);

        // transfer funds
        (bool success,) = address(lzReceiver).call{ value: ETH_AMOUNT }("");
        if (!success) revert TransferFailed();
        // trigger compose
        lzReceiver.lzCompose(ethPool, bytes32(0), message, address(0), "");
        uint256 balanceAfter = weth.balanceOf(address(this));
        assertEq(ETH_AMOUNT, balanceAfter - balanceBefore);
    }

    function testEthBridgeWithFailingShortcut() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = address(this).balance;

        // TOO MUCH VALUE ATTEMPTED TO TRANSFER
        (bytes32[] memory commands, bytes[] memory state) = _buildWethDeposit(ETH_AMOUNT * 100);
        bytes memory message = _buildLzComposeMessage(ETH_AMOUNT, commands, state);

        // transfer funds
        (bool success,) = address(lzReceiver).call{ value: ETH_AMOUNT }("");
        if (!success) revert TransferFailed();
        // confirm funds have left this address
        assertGt(balanceBefore, address(this).balance);
        // trigger compose
        lzReceiver.lzCompose(ethPool, bytes32(0), message, address(0), "");
        // confirm funds have been returned to this address
        assertEq(balanceBefore, address(this).balance);
    }

    function testEthBridgeWithInsufficientGas() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = address(this).balance;

        (bytes32[] memory commands, bytes[] memory state) = _buildWethDeposit(ETH_AMOUNT);
        bytes memory message = _buildLzComposeMessage(ETH_AMOUNT, commands, state);

        // transfer funds
        (bool success,) = address(lzReceiver).call{ value: ETH_AMOUNT }("");
        if (!success) revert TransferFailed();
        // confirm funds have left this address
        assertGt(balanceBefore, address(this).balance);
        // trigger compose with insufficient gas
        lzReceiver.lzCompose{ gas: 99_000 }(ethPool, bytes32(0), message, address(0), "");
        // confirm funds have been returned to this address
        assertEq(balanceBefore, address(this).balance);
    }

    function testUsdcBridge() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = IERC20(usdc).balanceOf(vitalik);

        (bytes32[] memory commands, bytes[] memory state) = _buildTransfer(usdc, vitalik, USDC_AMOUNT);
        bytes memory message = _buildLzComposeMessage(USDC_AMOUNT, commands, state);

        // transfer funds
        vm.startPrank(usdcPool);
        IERC20(usdc).transfer(address(lzReceiver), USDC_AMOUNT);
        vm.stopPrank();
        // trigger compose
        lzReceiver.lzCompose(usdcPool, bytes32(0), message, address(0), "");
        uint256 balanceAfter = IERC20(usdc).balanceOf(vitalik);
        assertEq(USDC_AMOUNT, balanceAfter - balanceBefore);
    }

    function testTokenAndNativeDropBridge() public {
        vm.selectFork(_ethereumFork);

        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(vitalik);
        uint256 ethBalanceBefore = vitalik.balance;

        (bytes32[] memory commands, bytes[] memory state) =
            _buildTokenAndValueTransfer(usdc, vitalik, USDC_AMOUNT, ETH_AMOUNT);
        bytes memory message = _buildLzComposeMessage(USDC_AMOUNT, commands, state);

        // transfer funds
        vm.startPrank(usdcPool);
        IERC20(usdc).transfer(address(lzReceiver), USDC_AMOUNT);
        vm.stopPrank();
        // trigger compose with msg.value
        lzReceiver.lzCompose{ value: ETH_AMOUNT }(usdcPool, bytes32(0), message, address(0), "");

        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(vitalik);
        uint256 ethBalanceAfter = vitalik.balance;

        assertEq(USDC_AMOUNT, usdcBalanceAfter - usdcBalanceBefore);
        assertEq(ETH_AMOUNT, ethBalanceAfter - ethBalanceBefore);
    }

    function testUsdcBridgeWithFailingShortcut() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = IERC20(usdc).balanceOf(address(this));

        // TOO MUCH VALUE ATTEMPTED TO TRANSFER
        (bytes32[] memory commands, bytes[] memory state) = _buildTransfer(usdc, vitalik, USDC_AMOUNT * 100);
        bytes memory message = _buildLzComposeMessage(USDC_AMOUNT, commands, state);

        // transfer funds
        vm.startPrank(usdcPool);
        IERC20(usdc).transfer(address(lzReceiver), USDC_AMOUNT);
        vm.stopPrank();
        // confirm funds have landed in the stargate receiver
        assertGt(IERC20(usdc).balanceOf(address(lzReceiver)), 0);
        // trigger compose
        lzReceiver.lzCompose(usdcPool, bytes32(0), message, address(0), "");
        // confirm funds have left the stargate receiver
        assertEq(IERC20(usdc).balanceOf(address(lzReceiver)), 0);
        // confirm funds have been returned this address
        uint256 balanceAfter = IERC20(usdc).balanceOf(address(this));
        assertEq(USDC_AMOUNT, balanceAfter - balanceBefore);
    }

    function testSweep() public {
        vm.selectFork(_ethereumFork);

        // transfer funds
        weth.deposit{ value: ETH_AMOUNT }();
        weth.transfer(address(lzReceiver), ETH_AMOUNT);
        (bool success,) = address(lzReceiver).call{ value: ETH_AMOUNT }("");
        (success); // shh

        uint256 ethOnReceiver = address(lzReceiver).balance;
        uint256 wethOnReceiver = weth.balanceOf(address(lzReceiver));

        uint256 ethBalanceBefore = address(this).balance;
        uint256 wethBalanceBefore = weth.balanceOf(address(this));

        // sweep
        address[] memory tokens = new address[](2);
        tokens[0] = eth;
        tokens[1] = address(weth);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = address(lzReceiver).balance;
        amounts[1] = weth.balanceOf(address(lzReceiver));
        lzReceiver.sweep(tokens, amounts);

        uint256 ethBalanceAfter = address(this).balance;
        uint256 wethBalanceAfter = weth.balanceOf(address(this));
        assertEq(ethOnReceiver, ethBalanceAfter - ethBalanceBefore);
        assertEq(wethOnReceiver, wethBalanceAfter - wethBalanceBefore);
    }

    receive() external payable { }

    function _buildLzComposeMessage(
        uint256 amount,
        bytes32[] memory commands,
        bytes[] memory state
    )
        internal
        view
        returns (bytes memory message)
    {
        // encode shortcut data
        bytes memory shortcutData =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);
        // encode callback data
        bytes memory callbackData = abi.encode(address(this), shortcutData);
        // encode message
        message = OFTComposeMsgCodec.encode(
            uint64(0),
            uint32(0),
            amount,
            abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(address(this)), callbackData)
        );
    }

    function _buildWethDeposit(uint256 amount)
        internal
        view
        returns (bytes32[] memory commands, bytes[] memory state)
    {
        // Setup script to deposit and transfer weth
        commands = new bytes32[](2);
        state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // value call
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        commands[1] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0100ffffffff, // 2 inputs
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(this));
    }

    function _buildWethWithdraw(uint256 amount)
        internal
        view
        returns (bytes32[] memory commands, bytes[] memory state)
    {
        // Setup script to withdraw weth and transfer eth
        commands = new bytes32[](2);
        state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        commands[1] = WeirollPlanner.buildCommand(
            0x00000000,
            0x23, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(this)
        );

        state[0] = abi.encode(amount);
        state[1] = ""; // Empty state for transfer of eth
    }

    function _buildTransfer(
        address token,
        address receiver,
        uint256 amount
    )
        internal
        pure
        returns (bytes32[] memory commands, bytes[] memory state)
    {
        // Setup script to transfer token
        commands = new bytes32[](1);
        state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            IERC20.transfer.selector,
            0x01, // call
            0x0001ffffffff, // 1 input
            0xff, // no output
            token
        );

        state[0] = abi.encode(receiver);
        state[1] = abi.encode(amount);
    }

    function _buildTokenAndValueTransfer(
        address token,
        address receiver,
        uint256 amount,
        uint256 value
    )
        internal
        pure
        returns (bytes32[] memory commands, bytes[] memory state)
    {
        // Setup script to transfer token
        commands = new bytes32[](2);
        state = new bytes[](4);

        commands[0] = WeirollPlanner.buildCommand(
            IERC20.transfer.selector,
            0x01, // call
            0x0001ffffffff, // 1 input
            0xff, // no output
            token
        );

        commands[1] = WeirollPlanner.buildCommand(
            0x00000000,
            0x23, // call
            0x0203ffffffff, // 2 inputs
            0xff, // no output
            receiver
        );

        state[0] = abi.encode(receiver);
        state[1] = abi.encode(amount);
        state[2] = abi.encode(value);
        state[3] = ""; // Empty state for transfer of eth
    }
}

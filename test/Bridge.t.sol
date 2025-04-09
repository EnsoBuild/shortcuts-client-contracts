// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { StargateV2Receiver } from "../src/bridge/StargateV2Receiver.sol";
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

contract BridgeTest is Test {
    StargateV2Receiver public stargateReceiver;
    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    uint256 public constant AMOUNT = 10 ** 18;

    error TransferFailed();

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        stargateReceiver = new StargateV2Receiver(address(this));
    }

    function testEthBridge() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = weth.balanceOf(address(this));

        (bytes32[] memory commands, bytes[] memory state) = _buildWethDeposit(AMOUNT);
        bytes memory message = _buildLzComposeMessage(eth, AMOUNT, commands, state);

        // transfer funds
        (bool success,) = address(stargateReceiver).call{ value: AMOUNT }("");
        if (!success) revert TransferFailed();
        // trigger compose
        stargateReceiver.lzCompose(address(0), bytes32(0), message, address(0), "");
        uint256 balanceAfter = weth.balanceOf(address(this));
        assertEq(AMOUNT, balanceAfter - balanceBefore);
    }

    function testEthBridgeWithFailingShortcut() public {
        vm.selectFork(_ethereumFork);

        uint256 balanceBefore = address(this).balance;

        // TOO MUCH VALUE ATTEMPTED TO TRANSFER
        (bytes32[] memory commands, bytes[] memory state) = _buildWethDeposit(AMOUNT * 100);
        bytes memory message = _buildLzComposeMessage(eth, AMOUNT, commands, state);

        // transfer funds
        (bool success,) = address(stargateReceiver).call{ value: AMOUNT }("");
        if (!success) revert TransferFailed();
        // confirm funds have left this address
        assertGt(balanceBefore, address(this).balance);
        // trigger compose
        stargateReceiver.lzCompose(address(0), bytes32(0), message, address(0), "");
        // confirm funds have been returned to this address
        assertEq(balanceBefore, address(this).balance);
    }

    function testWethBridge() public {
        vm.selectFork(_ethereumFork);

        weth.deposit{ value: AMOUNT }();
        uint256 balanceBefore = address(this).balance;

        (bytes32[] memory commands, bytes[] memory state) = _buildWethWithdraw(AMOUNT);
        bytes memory message = _buildLzComposeMessage(address(weth), AMOUNT, commands, state);

        // transfer funds
        weth.transfer(address(stargateReceiver), AMOUNT);
        // trigger compose
        stargateReceiver.lzCompose(address(0), bytes32(0), message, address(0), "");
        uint256 balanceAfter = address(this).balance;
        assertEq(AMOUNT, balanceAfter - balanceBefore);
    }

    function testWethBridgeWithFailingShortcut() public {
        vm.selectFork(_ethereumFork);

        weth.deposit{ value: AMOUNT }();
        uint256 balanceBefore = weth.balanceOf(address(this));

        // TOO MUCH VALUE ATTEMPTED TO TRANSFER
        (bytes32[] memory commands, bytes[] memory state) = _buildWethWithdraw(AMOUNT * 100);
        bytes memory message = _buildLzComposeMessage(address(weth), AMOUNT, commands, state);

        // transfer funds
        weth.transfer(address(stargateReceiver), AMOUNT);
        // confirm funds have left this address
        assertGt(balanceBefore, weth.balanceOf(address(this)));
        // trigger compose
        stargateReceiver.lzCompose(address(0), bytes32(0), message, address(0), "");
        // confirm funds have been returned to this address
        assertEq(balanceBefore, weth.balanceOf(address(this)));
    }

    receive() external payable { }

    function _buildLzComposeMessage(
        address token,
        uint256 amount,
        bytes32[] memory commands,
        bytes[] memory state
    )
        internal
        view
        returns (bytes memory message)
    {
        // encode callback data
        bytes memory callbackData = abi.encode(token, address(this), bytes32(0), commands, state);
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
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SwapHelpers } from "../../../../src/helpers/SwapHelpers.sol";
import { IDeepstateV1 } from "../../../../src/interfaces/IDeepstateV1.sol";
import { MockERC20 } from "../../../mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract MockDeepstateV1 is IDeepstateV1 {
    IERC20 internal constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IERC20 public tokenIn;
    IERC20 public tokenOut;
    uint256 public inputSpent;
    uint256 public outputAmount;
    bool public allNoRest;
    bool public firstFillOrKill;

    function configure(IERC20 tokenIn_, IERC20 tokenOut_, uint256 inputSpent_, uint256 outputAmount_) external {
        tokenIn = tokenIn_;
        tokenOut = tokenOut_;
        inputSpent = inputSpent_;
        outputAmount = outputAmount_;
    }

    function fillRoute(FillParams[] calldata fills) external payable {
        allNoRest = fills.length != 0;
        firstFillOrKill = fills.length != 0 && fills[0].fillOrKill;
        for (uint256 i; i < fills.length;) {
            allNoRest = allNoRest && fills[i].noRest;
            unchecked {
                ++i;
            }
        }

        if (tokenIn == _ETH) {
            payable(msg.sender).transfer(msg.value - inputSpent);
        } else {
            tokenIn.transferFrom(msg.sender, address(this), inputSpent);
        }

        if (tokenOut == _ETH) {
            payable(msg.sender).transfer(outputAmount);
        } else {
            tokenOut.transfer(msg.sender, outputAmount);
        }
    }

    receive() external payable { }
}

contract SwapHelpersDeepstateTest is Test {
    IERC20 internal constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address internal constant RECEIVER = address(0xBEEF);

    SwapHelpers internal helper;
    MockDeepstateV1 internal deepstate;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;

    function setUp() public {
        helper = new SwapHelpers();
        deepstate = new MockDeepstateV1();
        tokenIn = new MockERC20("Input", "IN");
        tokenOut = new MockERC20("Output", "OUT");
    }

    function test_swapDeepstate_refundsUnspentERC20AndForcesNoRest() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        uint256 amountOut = helper.swapDeepstate(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _fills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertTrue(deepstate.allNoRest());
        assertTrue(deepstate.firstFillOrKill());
    }

    function test_swapDeepstate_refundsUnspentNativeInput() public {
        vm.deal(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        deepstate.configure(_ETH, tokenOut, 60 ether, 70 ether);

        uint256 amountOut =
            helper.swapDeepstate{ value: 100 ether }(deepstate, _ETH, tokenOut, 100 ether, RECEIVER, _fills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(RECEIVER.balance, 40 ether);
        assertEq(address(deepstate).balance, 60 ether);
        assertEq(address(helper).balance, 0);
        assertTrue(deepstate.allNoRest());
    }

    function test_swapDeepstate_supportsNativeOutput() public {
        tokenIn.mint(address(this), 100 ether);
        tokenIn.approve(address(helper), 100 ether);
        vm.deal(address(deepstate), 70 ether);
        deepstate.configure(tokenIn, _ETH, 60 ether, 70 ether);

        uint256 amountOut = helper.swapDeepstate(deepstate, tokenIn, _ETH, 100 ether, RECEIVER, _fills());

        assertEq(amountOut, 70 ether);
        assertEq(RECEIVER.balance, 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(address(helper).balance, 0);
    }

    function test_swapDeepstate_revertsForSameAsset() public {
        vm.expectRevert(SwapHelpers.InvalidPair.selector);
        helper.swapDeepstate(deepstate, tokenIn, tokenIn, 0, RECEIVER, _fills());
    }

    function _fills() internal view returns (IDeepstateV1.FillParams[] memory fills) {
        fills = new IDeepstateV1.FillParams[](2);
        fills[0] = IDeepstateV1.FillParams({
            token0: address(tokenIn),
            token1: address(tokenOut),
            epoch: 0,
            order: bytes32(uint256(1)),
            isBid: true,
            noRest: false,
            fillOrKill: true
        });
        fills[1] = IDeepstateV1.FillParams({
            token0: address(tokenIn),
            token1: address(tokenOut),
            epoch: 0,
            order: bytes32(uint256(2)),
            isBid: false,
            noRest: false,
            fillOrKill: false
        });
    }
}

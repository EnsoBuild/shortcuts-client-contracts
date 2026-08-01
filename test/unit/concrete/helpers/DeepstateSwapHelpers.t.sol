// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { DeepstateV1 } from "../../../../lib/deepstate-contracts/src/DeepstateV1.sol";
import { DeepstateSwapHelpers } from "../../../../src/helpers/DeepstateSwapHelpers.sol";
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
            require(tokenIn.transferFrom(msg.sender, address(this), inputSpent));
        }

        if (tokenOut == _ETH) {
            payable(msg.sender).transfer(outputAmount);
        } else {
            require(tokenOut.transfer(msg.sender, outputAmount));
        }
    }

    receive() external payable { }
}

contract DeepstateSwapHelpersTest is Test {
    IERC20 internal constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address internal constant RECEIVER = address(0xBEEF);

    DeepstateSwapHelpers internal helper;
    MockDeepstateV1 internal deepstate;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;

    function setUp() public {
        helper = new DeepstateSwapHelpers();
        deepstate = new MockDeepstateV1();
        tokenIn = new MockERC20("Input", "IN");
        tokenOut = new MockERC20("Output", "OUT");
    }

    function test_swap_refundsUnspentERC20AndForcesNoRest() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        uint256 amountOut = helper.swap(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertTrue(deepstate.allNoRest());
        assertTrue(deepstate.firstFillOrKill());
    }

    function test_swap_refundsUnspentNativeInput() public {
        vm.deal(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        deepstate.configure(_ETH, tokenOut, 60 ether, 70 ether);

        uint256 amountOut =
            helper.swap{ value: 100 ether }(deepstate, _ETH, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(RECEIVER.balance, 40 ether);
        assertEq(address(deepstate).balance, 60 ether);
        assertEq(address(helper).balance, 0);
        assertTrue(deepstate.allNoRest());
    }

    function test_swap_supportsNativeOutput() public {
        tokenIn.mint(address(this), 100 ether);
        tokenIn.approve(address(helper), 100 ether);
        vm.deal(address(deepstate), 70 ether);
        deepstate.configure(tokenIn, _ETH, 60 ether, 70 ether);

        uint256 amountOut = helper.swap(deepstate, tokenIn, _ETH, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(RECEIVER.balance, 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(address(helper).balance, 0);
    }

    function test_swap_revertsForSameAsset() public {
        vm.expectRevert(DeepstateSwapHelpers.InvalidPair.selector);
        helper.swap(deepstate, tokenIn, tokenIn, 0, RECEIVER, _mockFills());
    }

    function test_swap_executesAgainstPinnedDeepstateAndDoesNotRestRemainder() public {
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");
        (MockERC20 token0, MockERC20 token1) = address(a) < address(b) ? (a, b) : (b, a);
        DeepstateV1 engine = new DeepstateV1();
        address maker = address(0xA11CE);

        token0.mint(maker, 60);
        vm.startPrank(maker);
        token0.approve(address(engine), 60);
        engine.fill(_engineFill(token0, token1, _order(60), false, false));
        vm.stopPrank();

        token1.mint(address(this), 100);
        token1.approve(address(helper), 100);
        IDeepstateV1.FillParams[] memory route = new IDeepstateV1.FillParams[](1);
        route[0] = _interfaceFill(token0, token1, _order(100), true, false);

        uint256 amountOut = helper.swap(IDeepstateV1(address(engine)), token1, token0, 100, RECEIVER, route);

        assertEq(amountOut, 60);
        assertEq(token0.balanceOf(RECEIVER), 60);
        assertEq(token1.balanceOf(RECEIVER), 40);
        assertEq(token0.balanceOf(address(helper)), 0);
        assertEq(token1.balanceOf(address(helper)), 0);
        assertEq(engine.nextNonce(address(token0), address(token1), 0), type(uint32).max - 1);
    }

    function test_swap_bridgesEnsoNativeSentinelToPinnedDeepstateNativeRoute() public {
        MockERC20 quoteToken = new MockERC20("Quote", "QUOTE");
        DeepstateV1 engine = new DeepstateV1();
        address maker = address(0xA11CE);

        quoteToken.mint(maker, 60);
        vm.startPrank(maker);
        quoteToken.approve(address(engine), 60);
        engine.fill(_engineNativeFill(quoteToken, _order(60), true));
        vm.stopPrank();

        vm.deal(address(this), 100);
        IDeepstateV1.FillParams[] memory route = new IDeepstateV1.FillParams[](1);
        route[0] = _interfaceNativeFill(quoteToken, _order(100), false);

        uint256 amountOut =
            helper.swap{ value: 100 }(IDeepstateV1(address(engine)), _ETH, quoteToken, 100, RECEIVER, route);

        assertEq(amountOut, 60);
        assertEq(quoteToken.balanceOf(RECEIVER), 60);
        assertEq(RECEIVER.balance, 40);
        assertEq(address(helper).balance, 0);
        assertEq(engine.nextNonce(address(0), address(quoteToken), 0), type(uint32).max - 1);
    }

    function _mockFills() internal view returns (IDeepstateV1.FillParams[] memory fills) {
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

    function _engineFill(
        MockERC20 token0,
        MockERC20 token1,
        bytes32 order,
        bool isBid,
        bool fillOrKill
    )
        private
        pure
        returns (DeepstateV1.FillParams memory)
    {
        return DeepstateV1.FillParams({
            token0: address(token0),
            token1: address(token1),
            epoch: 0,
            order: order,
            isBid: isBid,
            noRest: false,
            fillOrKill: fillOrKill
        });
    }

    function _interfaceFill(
        MockERC20 token0,
        MockERC20 token1,
        bytes32 order,
        bool isBid,
        bool fillOrKill
    )
        private
        pure
        returns (IDeepstateV1.FillParams memory)
    {
        return IDeepstateV1.FillParams({
            token0: address(token0),
            token1: address(token1),
            epoch: 0,
            order: order,
            isBid: isBid,
            noRest: false,
            fillOrKill: fillOrKill
        });
    }

    function _engineNativeFill(
        MockERC20 quoteToken,
        bytes32 order,
        bool isBid
    )
        private
        pure
        returns (DeepstateV1.FillParams memory)
    {
        return DeepstateV1.FillParams({
            token0: address(0),
            token1: address(quoteToken),
            epoch: 0,
            order: order,
            isBid: isBid,
            noRest: false,
            fillOrKill: false
        });
    }

    function _interfaceNativeFill(
        MockERC20 quoteToken,
        bytes32 order,
        bool isBid
    )
        private
        pure
        returns (IDeepstateV1.FillParams memory)
    {
        return IDeepstateV1.FillParams({
            token0: address(0),
            token1: address(quoteToken),
            epoch: 0,
            order: order,
            isBid: isBid,
            noRest: false,
            fillOrKill: false
        });
    }

    function _order(uint160 quantity) private pure returns (bytes32) {
        return bytes32(uint256(quantity) << 64);
    }
}

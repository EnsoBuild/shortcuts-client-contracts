// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../../../../src/helpers/PropAMMSwapHelpers.sol";
import { MockERC20 } from "../../../mocks/MockERC20.sol";
import {
    MockCurveLegacyPool,
    MockCurvePool,
    MockPropAMM,
    MockUniswapV3Pool
} from "../../../mocks/MockPropAMMVenues.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Test } from "forge-std/Test.sol";

contract PropAMMSwapHelpersTest is Test {
    PropAMMSwapHelpers.FallbackProtocol internal constant V3 = PropAMMSwapHelpers.FallbackProtocol.UniswapV3;
    PropAMMSwapHelpers.FallbackProtocol internal constant V4 = PropAMMSwapHelpers.FallbackProtocol.UniswapV4;
    PropAMMSwapHelpers.FallbackProtocol internal constant CURVE = PropAMMSwapHelpers.FallbackProtocol.Curve;
    PropAMMSwapHelpers.Outcome internal constant FILLED = PropAMMSwapHelpers.Outcome.PropAMMFilled;
    PropAMMSwapHelpers.Outcome internal constant SKIPPED = PropAMMSwapHelpers.Outcome.PropAMMSkipped;
    PropAMMSwapHelpers.Outcome internal constant FAILED = PropAMMSwapHelpers.Outcome.PropAMMFailed;

    uint256 internal constant AMOUNT_IN = 1e18;
    // The default pAMM pays a fixed 2 tokenOut per tokenIn, the default fallback (a Curve pool) 1.99.
    uint256 internal constant PAMM_OUT = 2e18;
    uint256 internal constant FALLBACK_OUT = 1.99e18;

    PropAMMSwapHelpers internal helper;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockPropAMM internal pamm;
    MockCurvePool internal curve;

    address internal receiver = makeAddr("receiver");

    function setUp() public {
        helper = new PropAMMSwapHelpers(IPoolManager(address(0)));
        tokenIn = new MockERC20("In", "IN");
        tokenOut = new MockERC20("Out", "OUT");
        pamm = new MockPropAMM(PAMM_OUT);

        curve = _curvePool(FALLBACK_OUT);

        tokenIn.mint(address(this), 100e18);
        tokenIn.approve(address(helper), type(uint256).max);
    }

    // --- Venue selection ---

    function test_pammFills() public {
        _expectSwapEvent(PAMM_OUT, FILLED, CURVE);
        uint256 amountOut = _swapDefault(0);

        assertEq(amountOut, PAMM_OUT, "pAMM amount");
        assertEq(tokenOut.balanceOf(receiver), PAMM_OUT, "receiver credited");
        assertEq(pamm.swapCalls(), 1, "pAMM called");
        assertEq(pamm.lastMinAmountOut(), 1, "pAMM floor is 1 without a caller minimum");
        assertEq(tokenIn.balanceOf(address(pamm)), AMOUNT_IN, "pAMM paid");
        _assertHelperEmpty();
    }

    function test_pammMinAmountOutIsTheCallerMinimum() public {
        _swapDefault(1.95e18);
        assertEq(pamm.lastMinAmountOut(), 1.95e18, "pAMM floor");
    }

    function test_pammQuotesBelowMinimum_skipped() public {
        pamm.setRate(1.9e18);

        _expectSwapEvent(FALLBACK_OUT, SKIPPED, CURVE);
        assertEq(_swapDefault(1.95e18), FALLBACK_OUT, "fallback amount");
        assertEq(pamm.swapCalls(), 0, "pAMM not called");
        _assertHelperEmpty();
    }

    function test_pammCannotQuote_skipped() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);

        _expectSwapEvent(FALLBACK_OUT, SKIPPED, CURVE);
        _swapDefault(0);
        assertEq(pamm.swapCalls(), 0, "pAMM not called");
    }

    function test_pammWithoutCode_fallbackFills() public {
        assertEq(_swapWith(makeAddr("noCode"), address(tokenOut), AMOUNT_IN, receiver), FALLBACK_OUT, "fallback");
    }

    function test_pammSwapReverts_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);

        _expectSwapEvent(FALLBACK_OUT, FAILED, CURVE);
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
        assertEq(tokenIn.balanceOf(address(pamm)), 0, "pAMM payment rolled back");
        _assertHelperEmpty();
    }

    function test_pammPaysNothing_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.PaysNothing);

        _expectSwapEvent(FALLBACK_OUT, FAILED, CURVE);
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
    }

    function test_pammPaysLessThanMinimum_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.PaysHalf);

        _expectSwapEvent(FALLBACK_OUT, FAILED, CURVE);
        assertEq(_swapDefault(1.5e18), FALLBACK_OUT, "fallback amount");
        assertEq(tokenOut.balanceOf(receiver), FALLBACK_OUT, "no partial pAMM output kept");
    }

    function test_pammPaysLessThanFallbackButAboveMinimum_filled() public {
        // The fallback is never quoted, so a pAMM paying above `minAmountOut` fills even below the fallback.
        pamm.setMode(MockPropAMM.Mode.PaysHalf);

        _expectSwapEvent(PAMM_OUT / 2, FILLED, CURVE);
        assertEq(_swapDefault(0), PAMM_OUT / 2, "pAMM amount");
    }

    function test_fallbackFailsToo_reverts() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        vm.expectRevert();
        _swap(V3, abi.encode(makeAddr("noPool")), 0);
    }

    function test_brokenFallback_pammStillFills() public {
        assertEq(_swap(V3, abi.encode(makeAddr("noPool")), 0), PAMM_OUT, "pAMM amount");
    }

    // --- Output and input checks ---

    function test_minAmountOutNotMet_reverts() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        vm.expectRevert(
            abi.encodeWithSelector(PropAMMSwapHelpers.InsufficientOutputAmount.selector, FALLBACK_OUT, FALLBACK_OUT + 1)
        );
        _swapDefault(FALLBACK_OUT + 1);
    }

    function test_identicalTokens_reverts() public {
        vm.expectRevert(PropAMMSwapHelpers.IdenticalTokens.selector);
        _swapWith(address(pamm), address(tokenIn), AMOUNT_IN, receiver);
    }

    function test_zeroAmountIn_reverts() public {
        vm.expectRevert(PropAMMSwapHelpers.ZeroAmountIn.selector);
        _swapWith(address(pamm), address(tokenOut), 0, receiver);
    }

    function test_receiverIsHelper_reverts() public {
        vm.expectRevert(PropAMMSwapHelpers.InvalidReceiver.selector);
        _swapWith(address(pamm), address(tokenOut), AMOUNT_IN, address(helper));
    }

    // --- Uniswap V3 fallback ---

    function test_uniswapV3_fills() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        MockUniswapV3Pool pool = _v3Pool(2.01e18, false);

        assertApproxEqAbs(_swap(V3, abi.encode(address(pool)), 0), 2.01e18, 1, "fill");
        _assertHelperEmpty();
    }

    function test_pancakeV3Callback() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockUniswapV3Pool pool = _v3Pool(2e18, true);
        assertApproxEqAbs(_swap(V3, abi.encode(address(pool)), 0), 2e18, 1, "fill");
    }

    function test_uniswapV3_partialFillReverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockUniswapV3Pool pool = _v3Pool(2e18, false);
        pool.setMaxAmountIn(AMOUNT_IN / 4);

        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.AmountInMismatch.selector, AMOUNT_IN / 4, AMOUNT_IN));
        _swap(V3, abi.encode(address(pool)), 0);
    }

    function test_uniswapV3_overchargeReverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockUniswapV3Pool pool = _v3Pool(2e18, false);
        pool.setOvercharge(1);
        tokenIn.mint(address(helper), 1); // stray balance the pool tries to take
        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.AmountInMismatch.selector, AMOUNT_IN + 1, AMOUNT_IN));
        _swap(V3, abi.encode(address(pool)), 0);
    }

    function test_uniswapV3Callbacks_rejectStranger() public {
        bytes memory data = abi.encode(address(tokenIn), uint256(1), false);
        vm.expectRevert(PropAMMSwapHelpers.InvalidCallback.selector);
        helper.uniswapV3SwapCallback(1, -1, data);
        vm.expectRevert(PropAMMSwapHelpers.InvalidCallback.selector);
        helper.pancakeV3SwapCallback(1, -1, data);
    }

    function test_uniswapV3WrongPair_reverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockERC20 other = new MockERC20("C", "C");
        MockUniswapV3Pool pool = new MockUniswapV3Pool(address(tokenIn), address(other), 5e18, false);
        vm.expectRevert(PropAMMSwapHelpers.FallbackTokenMismatch.selector);
        _swap(V3, abi.encode(address(pool)), 0);
    }

    function test_uniswapV3_forgedCallbackDataIgnored() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockUniswapV3Pool pool = _v3Pool(2e18, false);
        // The pool claims a different token and a huge amount in the callback data.
        MockERC20 stray = new MockERC20("Stray", "STRAY");
        stray.mint(address(helper), 10e18);
        pool.setForgedData(abi.encode(address(stray), uint256(10e18), false));

        uint256 balanceBefore = tokenIn.balanceOf(address(this));
        assertApproxEqAbs(_swap(V3, abi.encode(address(pool)), 0), 2e18, 1, "fill");
        assertEq(balanceBefore - tokenIn.balanceOf(address(this)), AMOUNT_IN, "paid in tokenIn");
        assertEq(stray.balanceOf(address(helper)), 10e18, "stray token untouched");
    }

    // --- Curve fallback ---

    function test_curveInt128_fills() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        MockCurvePool pool = _curvePool(2.01e18);

        assertEq(_swap(CURVE, abi.encode(address(pool), true, uint8(0), uint8(1)), 0), 2.01e18, "fill");
        assertEq(tokenIn.allowance(address(helper), address(pool)), 0, "approval cleared");
        _assertHelperEmpty();
    }

    function test_curveUint256_fills() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockCurvePool pool = _curvePool(2.5e18);
        assertEq(_swap(CURVE, abi.encode(address(pool), false, uint8(0), uint8(1)), 0), 2.5e18, "fill");
    }

    function test_curveLegacyCoinsGetter_fills() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        MockCurveLegacyPool pool = new MockCurveLegacyPool(address(tokenIn), address(tokenOut), 2.01e18);
        tokenOut.mint(address(pool), 1000e18);

        assertEq(_swap(CURVE, abi.encode(address(pool), true, uint8(0), uint8(1)), 0), 2.01e18, "fill");
        _assertHelperEmpty();
    }

    function test_curveWrongPair_reverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockCurvePool pool = new MockCurvePool(address(tokenIn), address(new MockERC20("C", "C")), 5e18);
        vm.expectRevert(PropAMMSwapHelpers.FallbackTokenMismatch.selector);
        _swap(CURVE, abi.encode(address(pool), false, uint8(0), uint8(1)), 0);
    }

    function test_curveSwappedIndices_reverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        vm.expectRevert(PropAMMSwapHelpers.FallbackTokenMismatch.selector);
        _swap(CURVE, abi.encode(address(curve), true, uint8(1), uint8(0)), 0);
    }

    // --- Uniswap V4 fallback ---

    function test_uniswapV4WithoutPoolManager_reverts() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.ProtocolUnavailable.selector, V4));
        _swap(V4, abi.encode(uint24(500), int24(10), address(0), bytes("")), 0);
    }

    function test_unlockCallback_rejectsStranger() public {
        vm.expectRevert(PropAMMSwapHelpers.InvalidCallback.selector);
        helper.unlockCallback("");
    }

    // --- Self-only entry point ---

    function test_executePropAMM_rejectsExternalCaller() public {
        vm.expectRevert(PropAMMSwapHelpers.NotSelf.selector);
        helper.executePropAMM(address(pamm), address(tokenIn), address(tokenOut), AMOUNT_IN, 0, receiver);
    }

    // --- Helpers ---

    function _swapDefault(uint256 minAmountOut) internal returns (uint256) {
        return _swap(CURVE, _curveData(), minAmountOut);
    }

    function _swap(
        PropAMMSwapHelpers.FallbackProtocol protocol,
        bytes memory data,
        uint256 minAmountOut
    )
        internal
        returns (uint256)
    {
        return helper.swap(
            address(pamm), address(tokenIn), address(tokenOut), AMOUNT_IN, minAmountOut, receiver, protocol, data
        );
    }

    /// @dev A default-fallback swap with one of the pAMM, `tokenOut`, `amountIn` or receiver changed.
    function _swapWith(
        address pamm_,
        address tokenOut_,
        uint256 amountIn_,
        address receiver_
    )
        internal
        returns (uint256)
    {
        return helper.swap(pamm_, address(tokenIn), tokenOut_, amountIn_, 0, receiver_, CURVE, _curveData());
    }

    function _curveData() internal view returns (bytes memory) {
        return abi.encode(address(curve), true, uint8(0), uint8(1));
    }

    /// @dev A pool paying `outPerIn` tokenOut per tokenIn, whichever of the two sorts first.
    function _v3Pool(uint256 outPerIn, bool pancake) internal returns (MockUniswapV3Pool pool) {
        uint256 rate = address(tokenIn) < address(tokenOut) ? outPerIn : 1e36 / outPerIn;
        pool = new MockUniswapV3Pool(address(tokenIn), address(tokenOut), rate, pancake);
        tokenOut.mint(address(pool), 1000e18);
    }

    function _curvePool(uint256 outPerIn) internal returns (MockCurvePool pool) {
        pool = new MockCurvePool(address(tokenIn), address(tokenOut), outPerIn);
        tokenOut.mint(address(pool), 1000e18);
    }

    function _expectSwapEvent(
        uint256 amountOut,
        PropAMMSwapHelpers.Outcome outcome,
        PropAMMSwapHelpers.FallbackProtocol protocol
    )
        internal
    {
        vm.expectEmit(address(helper));
        emit PropAMMSwapHelpers.PropAMMSwap(
            address(pamm), address(tokenIn), address(tokenOut), AMOUNT_IN, amountOut, receiver, outcome, protocol
        );
    }

    function _assertHelperEmpty() internal view {
        assertEq(tokenIn.balanceOf(address(helper)), 0, "helper holds tokenIn");
        assertEq(tokenOut.balanceOf(address(helper)), 0, "helper holds tokenOut");
    }
}

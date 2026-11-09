// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../../../../src/helpers/PropAMMSwapHelpers.sol";
import { SwapHelpers } from "../../../../src/helpers/SwapHelpers.sol";
import { MockERC20 } from "../../../mocks/MockERC20.sol";
import { MockCurvePool, MockPropAMM, MockRouter, MockTokenPuller } from "../../../mocks/MockPropAMMVenues.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test, Vm } from "forge-std/Test.sol";

contract PropAMMSwapHelpersTest is Test {
    PropAMMSwapHelpers.Outcome internal constant FILLED = PropAMMSwapHelpers.Outcome.PropAMMFilled;
    PropAMMSwapHelpers.Outcome internal constant SKIPPED = PropAMMSwapHelpers.Outcome.PropAMMSkipped;
    PropAMMSwapHelpers.Outcome internal constant FAILED = PropAMMSwapHelpers.Outcome.PropAMMFailed;

    uint256 internal constant AMOUNT_IN = 1e18;
    // The default pAMM pays a fixed 2 tokenOut per tokenIn, the default fallback (a Curve pool) 1.99.
    uint256 internal constant PAMM_OUT = 2e18;
    uint256 internal constant FALLBACK_OUT = 1.99e18;
    // `dx`, the third argument of Curve's `exchange(int128,int128,uint256,uint256)`.
    uint256 internal constant CURVE_DX_POINTER = 64;
    // `amountIn`, the third argument of `MockRouter.swapExactIn`.
    uint256 internal constant ROUTER_AMOUNT_POINTER = 64;

    PropAMMSwapHelpers internal helper;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockPropAMM internal pamm;
    MockCurvePool internal curve;

    address internal receiver = makeAddr("receiver");

    /// @dev A fallback call, as the backend builds it for `SwapHelpers`.
    struct Fallback {
        address target;
        address operator;
        bytes data;
        uint256[] pointers;
    }

    function setUp() public {
        helper = new PropAMMSwapHelpers();
        tokenIn = new MockERC20("In", "IN");
        tokenOut = new MockERC20("Out", "OUT");
        pamm = new MockPropAMM(PAMM_OUT);

        curve = new MockCurvePool(address(tokenIn), address(tokenOut), FALLBACK_OUT);
        tokenOut.mint(address(curve), 1000e18);

        tokenIn.mint(address(this), 100e18);
        tokenIn.approve(address(helper), type(uint256).max);
    }

    // --- Venue selection ---

    function test_pammFills() public {
        _expectSwapEvent(PAMM_OUT, FILLED, address(curve));
        uint256 amountOut = _swapDefault(0);

        assertEq(amountOut, PAMM_OUT, "pAMM amount");
        assertEq(tokenOut.balanceOf(receiver), PAMM_OUT, "receiver credited");
        assertEq(pamm.swapCalls(), 1, "pAMM called");
        assertEq(pamm.lastMinAmountOut(), PAMM_OUT, "pAMM minimum is its quote");
        assertEq(tokenIn.balanceOf(address(pamm)), AMOUNT_IN, "pAMM paid");
        assertEq(tokenIn.allowance(address(helper), address(curve)), 0, "fallback never approved");
        _assertHelperEmpty();
    }

    function test_pammMinimumIsItsQuoteNotTheCallerMinimum() public {
        _swapDefault(1.95e18);
        assertEq(pamm.lastMinAmountOut(), PAMM_OUT, "pAMM floor");
    }

    function test_pammQuotesBelowMinimum_skipped() public {
        pamm.setRate(1.9e18);

        _expectSwapEvent(FALLBACK_OUT, SKIPPED, address(curve));
        assertEq(_swapDefault(1.95e18), FALLBACK_OUT, "fallback amount");
        assertEq(pamm.swapCalls(), 0, "pAMM not called");
        _assertHelperEmpty();
    }

    function test_pammCannotQuote_skipped() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);

        _expectSwapEvent(FALLBACK_OUT, SKIPPED, address(curve));
        _swapDefault(0);
        assertEq(pamm.swapCalls(), 0, "pAMM not called");
    }

    function test_pammWithoutCode_fallbackFills() public {
        assertEq(_swapWith(makeAddr("noCode"), address(tokenOut), AMOUNT_IN, receiver), FALLBACK_OUT, "fallback");
    }

    function test_pammSwapReverts_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);

        _expectSwapEvent(FALLBACK_OUT, FAILED, address(curve));
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
        assertEq(tokenIn.balanceOf(address(pamm)), 0, "pAMM payment rolled back");
        _assertHelperEmpty();
    }

    function test_pammPaysNothing_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.PaysNothing);

        _expectSwapEvent(FALLBACK_OUT, FAILED, address(curve));
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
    }

    function test_pammPaysLessThanMinimum_fallsThrough() public {
        pamm.setMode(MockPropAMM.Mode.PaysHalf);

        _expectSwapEvent(FALLBACK_OUT, FAILED, address(curve));
        assertEq(_swapDefault(1.5e18), FALLBACK_OUT, "fallback amount");
        assertEq(tokenOut.balanceOf(receiver), FALLBACK_OUT, "no partial pAMM output kept");
    }

    function test_pammQuotesBelowFallback_stillFills() public {
        // The fallback is never quoted, so an honest pAMM priced below it but above `minAmountOut` fills.
        pamm.setRate(1.98e18);

        _expectSwapEvent(1.98e18, FILLED, address(curve));
        assertEq(_swapDefault(0), 1.98e18, "pAMM amount");
    }

    function test_pammPaysBelowQuote_fallsThrough() public {
        // Paying less than it just quoted fails the pAMM, even above `minAmountOut`.
        pamm.setMode(MockPropAMM.Mode.PaysHalf);

        _expectSwapEvent(FALLBACK_OUT, FAILED, address(curve));
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
        assertEq(tokenIn.balanceOf(address(pamm)), 0, "pAMM payment rolled back");
        _assertHelperEmpty();
    }

    function test_fallbackFailsToo_reverts() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        MockRouter router = _router(2e18, MockTokenPuller(address(0)));
        router.setReverts(true);

        vm.expectRevert("MockRouter: failed");
        _swap(_routerFallback(router, address(router), address(helper)), 0);
    }

    function test_brokenFallback_pammStillFills() public {
        MockRouter router = _router(2e18, MockTokenPuller(address(0)));
        router.setReverts(true);
        assertEq(_swap(_routerFallback(router, address(router), address(helper)), 0), PAMM_OUT, "pAMM amount");
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

    // --- Fallback call ---

    function test_fallback_insertsAmountAndForwardsOutput() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        // The calldata is built with a zero `dx`; the helper writes `amountIn` at the pointer.
        assertEq(_swapDefault(0), FALLBACK_OUT, "fallback amount");
        assertEq(tokenIn.balanceOf(address(curve)), AMOUNT_IN, "curve paid amountIn");
        assertEq(tokenIn.allowance(address(helper), address(curve)), 0, "approval cleared");
        _assertHelperEmpty();
    }

    function test_fallback_paysReceiverDirectly() public {
        pamm.setMode(MockPropAMM.Mode.SwapReverts);
        MockRouter router = _router(2.01e18, MockTokenPuller(address(0)));

        _expectSwapEvent(2.01e18, FAILED, address(router));
        assertEq(_swap(_routerFallback(router, address(router), receiver), 0), 2.01e18, "fill");
        _assertHelperEmpty();
    }

    function test_fallback_operatorDiffersFromTarget() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockTokenPuller puller = new MockTokenPuller();
        MockRouter router = _router(2e18, puller);

        assertEq(_swap(_routerFallback(router, address(puller), address(helper)), 0), 2e18, "fill");
        assertEq(tokenIn.allowance(address(helper), address(puller)), 0, "approval cleared");
        _assertHelperEmpty();
    }

    function test_fallback_swapHelpersAsTarget() public {
        // The fallback can be a `SwapHelpers` call itself, with its own nested amount pointers.
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        SwapHelpers swapHelpers = new SwapHelpers();
        MockRouter router = _router(2e18, MockTokenPuller(address(0)));
        Fallback memory inner = _routerFallback(router, address(router), address(swapHelpers));

        Fallback memory outer;
        outer.target = address(swapHelpers);
        outer.operator = address(swapHelpers);
        outer.data = abi.encodeWithSignature(
            "swap(address,address,address,uint256,address,bytes,uint256[])",
            address(router),
            address(tokenIn),
            address(tokenOut),
            uint256(0),
            receiver,
            inner.data,
            inner.pointers
        );
        // `amountIn`, the fourth argument.
        outer.pointers = _pointers(96);

        assertEq(_swap(outer, 0), 2e18, "fill");
        _assertHelperEmpty();
    }

    function test_fallback_multiplePointers() public view {
        bytes memory data = abi.encodeCall(MockRouter.swapExactIn, (address(1), address(2), 0, 0, address(3)));
        uint256[] memory pointers = new uint256[](2);
        pointers[0] = 64;
        pointers[1] = 96;

        bytes memory filled = helper.insertAmount(data, pointers, 7);
        assertEq(filled, abi.encodeCall(MockRouter.swapExactIn, (address(1), address(2), 7, 7, address(3))));
    }

    function test_fallback_partialFillReverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        MockRouter router = _router(2e18, MockTokenPuller(address(0)));
        router.setPullDivisor(4);

        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.AmountInMismatch.selector, AMOUNT_IN / 4, AMOUNT_IN));
        _swap(_routerFallback(router, address(router), address(helper)), 0);
    }

    function test_fallback_withoutPointerUsesEncodedAmount() public {
        // Without a pointer the calldata keeps its zero `dx`, so the pool takes nothing and the swap reverts.
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        Fallback memory fb = _curveFallback();
        fb.pointers = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.AmountInMismatch.selector, 0, AMOUNT_IN));
        _swap(fb, 0);
    }

    function test_fallback_targetWithoutCodeReverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        Fallback memory fb = _curveFallback();
        fb.target = makeAddr("noPool");

        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.AmountInMismatch.selector, 0, AMOUNT_IN));
        _swap(fb, 0);
    }

    function test_fallback_targetIsHelperReverts() public {
        Fallback memory fb = _curveFallback();
        fb.target = address(helper);

        vm.expectRevert(PropAMMSwapHelpers.InvalidFallbackTarget.selector);
        _swap(fb, 0);
    }

    function test_fallback_pointerOutOfBoundsReverts() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        Fallback memory fb = _curveFallback();
        // `exchange` has four words of arguments: offset 96 is the last one that fits.
        fb.pointers = _pointers(97);

        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.InvalidPointer.selector, 97));
        _swap(fb, 0);
    }

    function test_insertAmount_lastWordFits() public view {
        bytes memory data = abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)", 0, 1, 0, 0);
        bytes memory filled = helper.insertAmount(data, _pointers(96), 5);
        assertEq(filled, abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)", 0, 1, 0, 5));
    }

    function test_insertAmount_shortDataReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropAMMSwapHelpers.InvalidPointer.selector, 0));
        helper.insertAmount(hex"12345678", _pointers(0), 1);
    }

    // --- Payment and allowance ---

    function test_pammFills_paidStraightFromCaller() public {
        tokenIn.approve(address(helper), AMOUNT_IN);

        // The only tokenIn transfer is caller -> pAMM: the helper never holds it.
        vm.recordLogs();
        _swapDefault(0);
        _assertSingleTransfer(address(this), address(pamm));
        assertEq(tokenIn.allowance(address(this), address(helper)), 0, "allowance spent");
    }

    function test_pammFails_exactApprovalStillFallsBack() public {
        // The failed pAMM attempt rolls its pull back, so the exact allowance is still there for the fallback.
        pamm.setMode(MockPropAMM.Mode.PaysHalf);
        tokenIn.approve(address(helper), AMOUNT_IN);
        uint256 balanceBefore = tokenIn.balanceOf(address(this));

        assertEq(_swapDefault(1.5e18), FALLBACK_OUT, "fallback amount");
        assertEq(balanceBefore - tokenIn.balanceOf(address(this)), AMOUNT_IN, "paid once");
        assertEq(tokenIn.balanceOf(address(pamm)), 0, "pAMM payment rolled back");
        assertEq(tokenIn.allowance(address(this), address(helper)), 0, "allowance spent");
        _assertHelperEmpty();
    }

    function test_pammSkipped_pulledIntoHelperForFallback() public {
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
        tokenIn.approve(address(helper), AMOUNT_IN);

        vm.recordLogs();
        _swapDefault(0);
        // caller -> helper, then helper -> Curve.
        Vm.Log[] memory transfers = _tokenInTransfers();
        assertEq(transfers.length, 2, "two tokenIn transfers");
        assertEq(address(uint160(uint256(transfers[0].topics[1]))), address(this), "pulled from caller");
        assertEq(address(uint160(uint256(transfers[0].topics[2]))), address(helper), "into helper");
        assertEq(address(uint160(uint256(transfers[1].topics[2]))), address(curve), "then to Curve");
    }

    function test_insufficientAllowance_reverts() public {
        // The pAMM attempt fails on the pull and rolls back; the fallback pull then reverts the swap.
        tokenIn.approve(address(helper), AMOUNT_IN - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(helper), AMOUNT_IN - 1, AMOUNT_IN
            )
        );
        _swapDefault(0);
    }

    // --- Self-only entry point ---

    function test_executePropAMM_rejectsExternalCaller() public {
        vm.expectRevert(PropAMMSwapHelpers.NotSelf.selector);
        helper.executePropAMM(address(this), address(pamm), address(tokenIn), address(tokenOut), AMOUNT_IN, 0, receiver);
    }

    // --- Helpers ---

    function _swapDefault(uint256 minAmountOut) internal returns (uint256) {
        return _swap(_curveFallback(), minAmountOut);
    }

    function _swap(Fallback memory fb, uint256 minAmountOut) internal returns (uint256) {
        return helper.swap(
            address(pamm),
            address(tokenIn),
            address(tokenOut),
            AMOUNT_IN,
            minAmountOut,
            receiver,
            fb.target,
            fb.operator,
            fb.data,
            fb.pointers
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
        Fallback memory fb = _curveFallback();
        return helper.swap(
            pamm_, address(tokenIn), tokenOut_, amountIn_, 0, receiver_, fb.target, fb.operator, fb.data, fb.pointers
        );
    }

    /// @dev Curve `exchange(0, 1, dx, 0)`, paying the helper, with `dx` filled in by the helper.
    function _curveFallback() internal view returns (Fallback memory fb) {
        fb.target = address(curve);
        fb.operator = address(curve);
        fb.data = abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)", 0, 1, 0, 0);
        fb.pointers = _pointers(CURVE_DX_POINTER);
    }

    function _routerFallback(
        MockRouter router,
        address operator,
        address recipient
    )
        internal
        view
        returns (Fallback memory fb)
    {
        fb.target = address(router);
        fb.operator = operator;
        fb.data = abi.encodeCall(MockRouter.swapExactIn, (address(tokenIn), address(tokenOut), 0, 0, recipient));
        fb.pointers = _pointers(ROUTER_AMOUNT_POINTER);
    }

    function _router(uint256 rate, MockTokenPuller puller) internal returns (MockRouter) {
        return new MockRouter(rate, puller);
    }

    function _pointers(uint256 pointer) internal pure returns (uint256[] memory pointers) {
        pointers = new uint256[](1);
        pointers[0] = pointer;
    }

    function _expectSwapEvent(uint256 amountOut, PropAMMSwapHelpers.Outcome outcome, address fallbackTarget) internal {
        vm.expectEmit(address(helper));
        emit PropAMMSwapHelpers.PropAMMSwap(
            address(pamm), address(tokenIn), address(tokenOut), AMOUNT_IN, amountOut, receiver, outcome, fallbackTarget
        );
    }

    function _tokenInTransfers() internal returns (Vm.Log[] memory transfers) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        transfers = new Vm.Log[](logs.length);
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(tokenIn) && logs[i].topics[0] == IERC20.Transfer.selector) {
                transfers[count++] = logs[i];
            }
        }
        assembly ("memory-safe") {
            mstore(transfers, count)
        }
    }

    function _assertSingleTransfer(address from, address to) internal {
        Vm.Log[] memory transfers = _tokenInTransfers();
        assertEq(transfers.length, 1, "one tokenIn transfer");
        assertEq(address(uint160(uint256(transfers[0].topics[1]))), from, "from");
        assertEq(address(uint160(uint256(transfers[0].topics[2]))), to, "to");
    }

    function _assertHelperEmpty() internal view {
        assertEq(tokenIn.balanceOf(address(helper)), 0, "helper holds tokenIn");
        assertEq(tokenOut.balanceOf(address(helper)), 0, "helper holds tokenOut");
    }
}

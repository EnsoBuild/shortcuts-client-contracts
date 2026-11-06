// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../../../src/helpers/PropAMMSwapHelpers.sol";
import { UniswapV4SwapHelpers } from "../../../src/helpers/UniswapV4SwapHelpers.sol";
import { IPropAMM } from "../../../src/interfaces/IPropAMM.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockPropAMM } from "../../mocks/MockPropAMMVenues.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IV4Quoter } from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import { Test } from "forge-std/Test.sol";

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160, uint32, uint256);
}

/// @dev Uniswap SwapRouter02, which has no deadline in its params.
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface ICurve3Pool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external;
}

/// Ethereum fork: fallbacks built the way the backend builds `SwapHelpers` calls, against live venues, and a
/// live pAMM. Each fallback fill is checked against an independent quote: Uniswap's own quoters, and Curve's
/// `get_dy`. The mock pAMM forces each path: `QuoteReverts` makes the fallback run, a high rate makes the pAMM
/// fill.
contract PropAMMSwapHelpersForkTest is Test {
    using SafeERC20 for IERC20;

    struct Fallback {
        address target;
        address operator;
        bytes data;
        uint256[] pointers;
    }

    IQuoterV2 constant UNISWAP_V3_QUOTER = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IV4Quoter constant UNISWAP_V4_QUOTER = IV4Quoter(0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203);
    address constant SWAP_ROUTER_02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint24 constant UNISWAP_V3_USDC_WETH_FEE = 500;
    address constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // DAI, USDC, USDT
    // Uniswap V4 USDC/USDT 0.0007% pool without hooks, the deepest hookless one at the fork block.
    // PoolId 0x0fb0e40cec3bb23e13abc585958a93c796fbea56955e19a23727a716a0423239.
    uint24 constant UNISWAP_V4_USDC_USDT_FEE = 7;
    int24 constant UNISWAP_V4_USDC_USDT_TICK_SPACING = 1;

    // `amountIn` in each fallback's calldata, counted after the selector.
    uint256 constant SWAP_ROUTER_02_AMOUNT_POINTER = 128; // fifth word of the inline params struct
    uint256 constant CURVE_DX_POINTER = 64;
    uint256 constant V4_HELPERS_AMOUNT_POINTER = 192; // after the five-word PoolKey and `zeroForOne`

    // Titan pAMM venue (Tempest); outside a Titan-built block it may or may not quote.
    address constant TEMPEST = 0x00000003f1ec2379e79F58E12EC6C4F51Ee92149;

    PropAMMSwapHelpers helper;
    UniswapV4SwapHelpers v4Helpers;
    MockPropAMM pamm;
    address receiver = makeAddr("receiver");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"), 26_327_784);
        helper = new PropAMMSwapHelpers();
        v4Helpers = new UniswapV4SwapHelpers(UNIVERSAL_ROUTER, PERMIT2);
        pamm = new MockPropAMM(0);
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
    }

    function test_fallbackUniswapV3_fills() public {
        _assertFallbackFills(WETH, USDC, 1 ether, _v3Fallback(WETH, USDC), _v3Quote(WETH, USDC, 1 ether), 0);
    }

    function test_fallbackUniswapV3_reverse() public {
        _assertFallbackFills(USDC, WETH, 2000e6, _v3Fallback(USDC, WETH), _v3Quote(USDC, WETH, 2000e6), 0);
    }

    function test_fallbackCurve_fills() public {
        uint256 expected = ICurve3Pool(CURVE_3POOL).get_dy(1, 2, 1000e6);
        _assertFallbackFills(USDC, USDT, 1000e6, _curveFallback(1, 2), expected, 1);
        assertEq(IERC20(USDC).allowance(address(helper), CURVE_3POOL), 0, "approval cleared");
    }

    function test_fallbackCurve_usdtIn() public {
        // USDT's non-standard approve goes through forceApprove.
        uint256 expected = ICurve3Pool(CURVE_3POOL).get_dy(2, 1, 1000e6);
        _assertFallbackFills(USDT, USDC, 1000e6, _curveFallback(2, 1), expected, 1);
    }

    function test_fallbackUniswapV4_fills() public {
        // Through `UniswapV4SwapHelpers`, which pays `receiver` itself.
        _assertFallbackFills(USDC, USDT, 10_000e6, _v4Fallback(USDC, USDT), _v4Quote(USDC, USDT, 10_000e6), 0);
        _assertFallbackFills(USDT, USDC, 10_000e6, _v4Fallback(USDT, USDC), _v4Quote(USDT, USDC, 10_000e6), 0);
    }

    function test_pammFills_fallbackUntouched() public {
        // The pAMM quotes above `minAmountOut`, so it fills and the router is never approved or called.
        pamm.setMode(MockPropAMM.Mode.Normal);
        pamm.setRate(30_000e6);
        deal(WETH, address(this), 1 ether);
        IERC20(WETH).approve(address(helper), 1 ether);

        // The mock pAMM mints its output, which needs a mintable token: route its USDC through a stand-in.
        MockERC20 out = new MockERC20("Out", "OUT");
        Fallback memory fb = _v3Fallback(WETH, USDC);
        uint256 amountOut = helper.swap(
            address(pamm), WETH, address(out), 1 ether, 0, receiver, fb.target, fb.operator, fb.data, fb.pointers
        );
        assertEq(amountOut, 30_000e6, "pAMM filled");
        assertEq(pamm.swapCalls(), 1, "pAMM called");
        assertEq(IERC20(WETH).allowance(address(helper), SWAP_ROUTER_02), 0, "router never approved");
    }

    function test_livePamm_swapsOrFallsBack() public {
        // With the V3 price as `minAmountOut`, Tempest is only tried if it quotes at least that much, and the
        // receiver ends up with at least the V3 price either way.
        uint256 amountIn = 1 ether;
        uint256 v3Quote = _v3Quote(WETH, USDC, amountIn);
        try IPropAMM(TEMPEST).quote(WETH, USDC, amountIn) returns (uint256 pammQuote) {
            emit log_named_uint("tempest quote", pammQuote);
        } catch {
            emit log("tempest cannot quote");
        }
        emit log_named_uint("uniswap v3 quote", v3Quote);

        deal(WETH, address(this), amountIn);
        IERC20(WETH).approve(address(helper), amountIn);
        Fallback memory fb = _v3Fallback(WETH, USDC);
        uint256 amountOut = helper.swap(
            TEMPEST, WETH, USDC, amountIn, v3Quote, receiver, fb.target, fb.operator, fb.data, fb.pointers
        );

        assertGe(amountOut, v3Quote, "at least the V3 price");
        assertEq(IERC20(WETH).balanceOf(address(helper)), 0, "helper holds WETH");
        assertEq(IERC20(USDC).balanceOf(address(helper)), 0, "helper holds USDC");
    }

    // --- Helpers ---

    /// @dev Runs the fallback (the mock pAMM cannot quote) and checks it pays the independent quote `expected`.
    /// `tolerance` is how many wei the fill may fall short of it.
    function _assertFallbackFills(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        Fallback memory fb,
        uint256 expected,
        uint256 tolerance
    )
        internal
    {
        assertGt(expected, 0, "reference quote");

        deal(tokenIn, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(helper), amountIn);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);

        uint256 amountOut = helper.swap(
            address(pamm),
            tokenIn,
            tokenOut,
            amountIn,
            expected - tolerance,
            receiver,
            fb.target,
            fb.operator,
            fb.data,
            fb.pointers
        );

        assertApproxEqAbs(amountOut, expected, tolerance, "fill matches the reference quote");
        assertLe(amountOut, expected, "fill above the reference quote");
        assertEq(IERC20(tokenOut).balanceOf(receiver) - balanceBefore, amountOut, "receiver credited");
        assertEq(IERC20(tokenIn).balanceOf(address(helper)), 0, "helper holds tokenIn");
        assertEq(IERC20(tokenOut).balanceOf(address(helper)), 0, "helper holds tokenOut");
        assertEq(IERC20(tokenIn).allowance(address(helper), fb.operator), 0, "approval cleared");
    }

    /// @dev SwapRouter02 `exactInputSingle` on the USDC/WETH 0.05% pool, paying the helper.
    function _v3Fallback(address tokenIn, address tokenOut) internal view returns (Fallback memory fb) {
        fb.target = SWAP_ROUTER_02;
        fb.operator = SWAP_ROUTER_02;
        fb.data = abi.encodeCall(
            ISwapRouter02.exactInputSingle,
            (ISwapRouter02.ExactInputSingleParams(
                    tokenIn, tokenOut, UNISWAP_V3_USDC_WETH_FEE, address(helper), 0, 0, 0
                ))
        );
        fb.pointers = _pointers(SWAP_ROUTER_02_AMOUNT_POINTER);
    }

    /// @dev 3pool `exchange(i, j, dx, 0)`, paying the helper.
    function _curveFallback(int128 i, int128 j) internal pure returns (Fallback memory fb) {
        fb.target = CURVE_3POOL;
        fb.operator = CURVE_3POOL;
        fb.data = abi.encodeCall(ICurve3Pool.exchange, (i, j, 0, 0));
        fb.pointers = _pointers(CURVE_DX_POINTER);
    }

    /// @dev `UniswapV4SwapHelpers.swapExactInSingle` on the hookless USDC/USDT pool, paying `receiver` directly.
    function _v4Fallback(address tokenIn, address tokenOut) internal view returns (Fallback memory fb) {
        (PoolKey memory key, bool zeroForOne) = _v4Key(tokenIn, tokenOut);
        fb.target = address(v4Helpers);
        fb.operator = address(v4Helpers);
        fb.data = abi.encodeCall(
            UniswapV4SwapHelpers.swapExactInSingle, (key, zeroForOne, 0, 0, block.timestamp, receiver, bytes(""))
        );
        fb.pointers = _pointers(V4_HELPERS_AMOUNT_POINTER);
    }

    function _v3Quote(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        (amountOut,,,) = UNISWAP_V3_QUOTER.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, UNISWAP_V3_USDC_WETH_FEE, 0)
        );
    }

    function _v4Quote(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        (PoolKey memory key, bool zeroForOne) = _v4Key(tokenIn, tokenOut);
        (amountOut,) = UNISWAP_V4_QUOTER.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams(key, zeroForOne, uint128(amountIn), "")
        );
    }

    function _v4Key(address tokenIn, address tokenOut) internal pure returns (PoolKey memory key, bool zeroForOne) {
        zeroForOne = tokenIn < tokenOut;
        key = PoolKey(
            Currency.wrap(zeroForOne ? tokenIn : tokenOut),
            Currency.wrap(zeroForOne ? tokenOut : tokenIn),
            UNISWAP_V4_USDC_USDT_FEE,
            UNISWAP_V4_USDC_USDT_TICK_SPACING,
            IHooks(address(0))
        );
    }

    function _pointers(uint256 pointer) internal pure returns (uint256[] memory pointers) {
        pointers = new uint256[](1);
        pointers[0] = pointer;
    }
}

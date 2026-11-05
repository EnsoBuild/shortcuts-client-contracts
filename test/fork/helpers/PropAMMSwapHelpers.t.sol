// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../../../src/helpers/PropAMMSwapHelpers.sol";
import { IPropAMM } from "../../../src/interfaces/IPropAMM.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { MockPropAMM } from "../../mocks/MockPropAMMVenues.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
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

interface ICurve3Pool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

/// Ethereum fork: the fallback paths against live pools, and a live pAMM.
/// Each fallback fill is checked against an independent quote: Uniswap's own quoters, and Curve's `get_dy`.
/// The mock pAMM forces each path: `QuoteReverts` makes the fallback run, a high rate makes the pAMM fill.
contract PropAMMSwapHelpersForkTest is Test {
    using SafeERC20 for IERC20;

    IPoolManager constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    IQuoterV2 constant UNISWAP_V3_QUOTER = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IV4Quoter constant UNISWAP_V4_QUOTER = IV4Quoter(0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203);

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address constant UNISWAP_V3_USDC_WETH_500 = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // DAI, USDC, USDT
    // Uniswap V4 USDC/USDT 0.0007% pool without hooks, the deepest hookless one at the fork block.
    // PoolId 0x0fb0e40cec3bb23e13abc585958a93c796fbea56955e19a23727a716a0423239.
    uint24 constant UNISWAP_V4_USDC_USDT_FEE = 7;
    int24 constant UNISWAP_V4_USDC_USDT_TICK_SPACING = 1;

    // Titan pAMM venue (Tempest); outside a Titan-built block it may or may not quote.
    address constant TEMPEST = 0x00000003f1ec2379e79F58E12EC6C4F51Ee92149;

    PropAMMSwapHelpers helper;
    MockPropAMM pamm;
    address receiver = makeAddr("receiver");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"), 26_327_784);
        helper = new PropAMMSwapHelpers(POOL_MANAGER);
        pamm = new MockPropAMM(0);
        pamm.setMode(MockPropAMM.Mode.QuoteReverts);
    }

    function test_fallbackUniswapV3_fills() public {
        _assertFallbackFills(WETH, USDC, 1 ether, PropAMMSwapHelpers.FallbackProtocol.UniswapV3, _v3Data(), 0);
    }

    function test_fallbackUniswapV3_reverse() public {
        _assertFallbackFills(USDC, WETH, 2000e6, PropAMMSwapHelpers.FallbackProtocol.UniswapV3, _v3Data(), 0);
    }

    function test_fallbackCurve_fills() public {
        _assertFallbackFills(USDC, USDT, 1000e6, PropAMMSwapHelpers.FallbackProtocol.Curve, _curveData(1, 2), 1);
        assertEq(IERC20(USDC).allowance(address(helper), CURVE_3POOL), 0, "approval cleared");
    }

    function test_fallbackCurve_usdtIn() public {
        // USDT's non-standard approve goes through forceApprove.
        _assertFallbackFills(USDT, USDC, 1000e6, PropAMMSwapHelpers.FallbackProtocol.Curve, _curveData(2, 1), 1);
    }

    function test_fallbackUniswapV4_fills() public {
        bytes memory data =
            abi.encode(UNISWAP_V4_USDC_USDT_FEE, UNISWAP_V4_USDC_USDT_TICK_SPACING, address(0), bytes(""));

        _assertFallbackFills(USDC, USDT, 10_000e6, PropAMMSwapHelpers.FallbackProtocol.UniswapV4, data, 0);
        _assertFallbackFills(USDT, USDC, 10_000e6, PropAMMSwapHelpers.FallbackProtocol.UniswapV4, data, 0);
    }

    function test_pammFills_fallbackUntouched() public {
        // The pAMM quotes above `minAmountOut`, so it fills and the V3 pool is never touched.
        pamm.setMode(MockPropAMM.Mode.Normal);
        pamm.setRate(30_000e6);
        deal(WETH, address(this), 1 ether);
        IERC20(WETH).approve(address(helper), 1 ether);

        // The mock pAMM mints its output, which needs a mintable token: route its USDC through a stand-in.
        MockERC20 out = new MockERC20("Out", "OUT");
        uint256 amountOut = helper.swap(
            address(pamm),
            WETH,
            address(out),
            1 ether,
            0,
            receiver,
            PropAMMSwapHelpers.FallbackProtocol.UniswapV3,
            _v3Data()
        );
        assertEq(amountOut, 30_000e6, "pAMM filled");
        assertEq(pamm.swapCalls(), 1, "pAMM called");
    }

    function test_livePamm_swapsOrFallsBack() public {
        // With the V3 price as `minAmountOut`, Tempest is only tried if it quotes at least that much, and the
        // receiver ends up with at least the V3 price either way.
        uint256 amountIn = 1 ether;
        uint256 v3Quote = _referenceQuote(WETH, USDC, amountIn, PropAMMSwapHelpers.FallbackProtocol.UniswapV3, "");
        try IPropAMM(TEMPEST).quote(WETH, USDC, amountIn) returns (uint256 pammQuote) {
            emit log_named_uint("tempest quote", pammQuote);
        } catch {
            emit log("tempest cannot quote");
        }
        emit log_named_uint("uniswap v3 quote", v3Quote);

        deal(WETH, address(this), amountIn);
        IERC20(WETH).approve(address(helper), amountIn);
        uint256 amountOut = helper.swap(
            TEMPEST, WETH, USDC, amountIn, v3Quote, receiver, PropAMMSwapHelpers.FallbackProtocol.UniswapV3, _v3Data()
        );

        assertGe(amountOut, v3Quote, "at least the V3 price");
        assertEq(IERC20(WETH).balanceOf(address(helper)), 0, "helper holds WETH");
        assertEq(IERC20(USDC).balanceOf(address(helper)), 0, "helper holds USDC");
    }

    // --- Helpers ---

    /// @dev Runs the fallback (the mock pAMM cannot quote) and checks it pays the independent quote.
    /// `tolerance` is how many wei the fill may fall short of it.
    function _assertFallbackFills(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        PropAMMSwapHelpers.FallbackProtocol protocol,
        bytes memory data,
        uint256 tolerance
    )
        internal
    {
        uint256 expected = _referenceQuote(tokenIn, tokenOut, amountIn, protocol, data);
        assertGt(expected, 0, "reference quote");

        deal(tokenIn, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(helper), amountIn);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);

        uint256 amountOut =
            helper.swap(address(pamm), tokenIn, tokenOut, amountIn, expected - tolerance, receiver, protocol, data);

        assertApproxEqAbs(amountOut, expected, tolerance, "fill matches the reference quote");
        assertLe(amountOut, expected, "fill above the reference quote");
        assertEq(IERC20(tokenOut).balanceOf(receiver) - balanceBefore, amountOut, "receiver credited");
        assertEq(IERC20(tokenIn).balanceOf(address(helper)), 0, "helper holds tokenIn");
        assertEq(IERC20(tokenOut).balanceOf(address(helper)), 0, "helper holds tokenOut");
    }

    /// @dev Uniswap's own quoters for V3 (the USDC/WETH 0.05% pool) and V4 (the pool in `data`), `get_dy` for
    /// 3pool.
    function _referenceQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        PropAMMSwapHelpers.FallbackProtocol protocol,
        bytes memory data
    )
        internal
        returns (uint256)
    {
        if (protocol == PropAMMSwapHelpers.FallbackProtocol.UniswapV3) {
            (uint256 amountOut,,,) = UNISWAP_V3_QUOTER.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams(tokenIn, tokenOut, amountIn, 500, 0)
            );
            return amountOut;
        }
        if (protocol == PropAMMSwapHelpers.FallbackProtocol.UniswapV4) {
            (uint24 fee, int24 tickSpacing, address hooks, bytes memory hookData) =
                abi.decode(data, (uint24, int24, address, bytes));
            bool zeroForOne = tokenIn < tokenOut;
            PoolKey memory key = PoolKey(
                Currency.wrap(zeroForOne ? tokenIn : tokenOut),
                Currency.wrap(zeroForOne ? tokenOut : tokenIn),
                fee,
                tickSpacing,
                IHooks(hooks)
            );
            (uint256 amountOut,) = UNISWAP_V4_QUOTER.quoteExactInputSingle(
                IV4Quoter.QuoteExactSingleParams(key, zeroForOne, uint128(amountIn), hookData)
            );
            return amountOut;
        }
        (,, uint8 i, uint8 j) = abi.decode(data, (address, bool, uint8, uint8));
        return ICurve3Pool(CURVE_3POOL).get_dy(int128(uint128(i)), int128(uint128(j)), amountIn);
    }

    function _v3Data() internal pure returns (bytes memory) {
        return abi.encode(UNISWAP_V3_USDC_WETH_500);
    }

    function _curveData(uint8 i, uint8 j) internal pure returns (bytes memory) {
        return abi.encode(CURVE_3POOL, true, i, j);
    }
}

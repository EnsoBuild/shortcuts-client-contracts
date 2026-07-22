// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniswapV4SwapHelpers } from "../../../src/helpers/UniswapV4SwapHelpers.sol";
import { UniswapV4SwapHelpersRobinhood } from "../../../src/helpers/UniswapV4SwapHelpersRobinhood.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Test } from "forge-std/Test.sol";

interface IWETH9 {
    function deposit() external payable;
}

contract UniswapV4SwapHelpersRobinhoodForkTest is Test {
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x8876789976dEcBfCbBbe364623C63652db8C0904);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73; // currency0
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // currency1, 6 decimals
    uint24 constant FEE = 400;
    int24 constant TICK_SPACING = 8;

    uint256 constant AMOUNT_IN = 1e15; // 0.001 WETH

    UniswapV4SwapHelpersRobinhood helper;
    UniswapV4SwapHelpers oldHelper;

    function setUp() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_RPC_URL"), 16_565_000);
        helper = new UniswapV4SwapHelpersRobinhood(UNIVERSAL_ROUTER, PERMIT2);
        oldHelper = new UniswapV4SwapHelpers(UNIVERSAL_ROUTER, PERMIT2);
        vm.deal(address(this), 1 ether);
        IWETH9(WETH).deposit{ value: 1 ether }();
    }

    function _poolKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(USDG),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }

    function test_robinhoodHelper_swapSucceeds() public {
        IERC20(WETH).approve(address(helper), AMOUNT_IN);
        uint256 out = helper.swapExactInSingle(_poolKey(), true, AMOUNT_IN, 0, block.timestamp + 900, address(this), "");
        // V4Quoter returns ~1.9395 USDG (6 dec) for 0.001 WETH
        assertGt(out, 1_500_000, "amountOut too low");
        assertLt(out, 2_500_000, "amountOut too high");
        assertEq(IERC20(USDG).balanceOf(address(this)), out, "receiver not credited");
    }

    function test_canonicalHelper_reverts() public {
        IERC20(WETH).approve(address(oldHelper), AMOUNT_IN);
        vm.expectRevert();
        oldHelper.swapExactInSingle(_poolKey(), true, AMOUNT_IN, 0, block.timestamp + 900, address(this), "");
    }
}

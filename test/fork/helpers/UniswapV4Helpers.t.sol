// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PriceOutOfBounds, UniswapV4Helpers } from "../../../src/helpers/UniswapV4Helpers.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { Test } from "forge-std/Test.sol";

/// Base fork: top up ETH/USDC 0.05% position #3084927 with calldata from `encodeIncrease`.
contract UniswapV4HelpersForkTest is Test {
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    IPositionManager constant POSITION_MANAGER = IPositionManager(0x7C5f5A4bBd8fD63184577525326123B519429bDc);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // currency1, 6 decimals

    uint256 constant TOKEN_ID = 3_084_927; // currency0 = native ETH
    uint256 constant AMOUNT0_MAX = 1e15; // 0.001 ETH
    uint256 constant AMOUNT1_MAX = 5e6; // 5 USDC, deliberately more than the range needs
    uint160 constant NO_MIN = 0;
    uint160 constant NO_MAX = type(uint160).max;

    UniswapV4Helpers helper;
    address owner;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 51_724_776);
        helper = new UniswapV4Helpers(POOL_MANAGER);
        owner = IERC721(address(POSITION_MANAGER)).ownerOf(TOKEN_ID);

        vm.deal(owner, 1 ether);
        deal(USDC, owner, AMOUNT1_MAX);
        vm.startPrank(owner);
        IERC20(USDC).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(USDC, address(POSITION_MANAGER), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function test_encodeIncrease_addsLiquidityAndRefundsNativeSurplus() public {
        uint128 liquidityBefore = POSITION_MANAGER.getPositionLiquidity(TOKEN_ID);
        uint256 ethBefore = owner.balance;
        uint256 usdcBefore = IERC20(USDC).balanceOf(owner);

        bytes memory data = helper.encodeIncrease(
            address(POSITION_MANAGER), TOKEN_ID, AMOUNT0_MAX, AMOUNT1_MAX, NO_MIN, NO_MAX, owner
        );

        vm.prank(owner);
        POSITION_MANAGER.modifyLiquidities{ value: AMOUNT0_MAX }(data, block.timestamp + 900);

        assertGt(POSITION_MANAGER.getPositionLiquidity(TOKEN_ID), liquidityBefore, "liquidity not added");
        assertEq(IERC721(address(POSITION_MANAGER)).ownerOf(TOKEN_ID), owner, "owner changed");
        // Both legs bounded by the maxes; the off-ratio USDC surplus never leaves the owner
        // and the native surplus is swept back.
        uint256 ethSpent = ethBefore - owner.balance;
        uint256 usdcSpent = usdcBefore - IERC20(USDC).balanceOf(owner);
        assertLe(ethSpent, AMOUNT0_MAX, "spent more ETH than max");
        assertLe(usdcSpent, AMOUNT1_MAX, "spent more USDC than max");
        assertGt(ethSpent, 0, "no ETH spent");
        assertLt(usdcSpent, AMOUNT1_MAX, "expected USDC surplus");
        assertEq(address(POSITION_MANAGER).balance, 0, "native stuck in position manager");
    }

    function test_encodeIncrease_revertsForStranger() public {
        bytes memory data = helper.encodeIncrease(
            address(POSITION_MANAGER), TOKEN_ID, AMOUNT0_MAX, AMOUNT1_MAX, NO_MIN, NO_MAX, address(this)
        );
        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        POSITION_MANAGER.modifyLiquidities{ value: AMOUNT0_MAX }(data, block.timestamp + 900);
    }
}

/// Base fork, fresh pool with known liquidity: the price window and the fee-credit settlement.
contract UniswapV4HelpersIncreaseBoundsTest is Test {
    IPoolManager constant POOL_MANAGER = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
    IPositionManager constant POSM = IPositionManager(0x7C5f5A4bBd8fD63184577525326123B519429bDc);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint8 constant MINT_POSITION = 0x02;
    uint8 constant SETTLE_PAIR = 0x0d;

    UniswapV4Helpers helper;
    PoolSwapTest swapper;
    PoolKey key;
    MockERC20 t0;
    MockERC20 t1;
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");
    address lp = makeAddr("lp");

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 51_724_776);
        helper = new UniswapV4Helpers(address(POOL_MANAGER));
        swapper = new PoolSwapTest(POOL_MANAGER);
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");
        (t0, t1) = address(a) < address(b) ? (a, b) : (b, a);
        key = PoolKey(Currency.wrap(address(t0)), Currency.wrap(address(t1)), 3000, 60, IHooks(address(0)));
        POOL_MANAGER.initialize(key, TickMath.getSqrtPriceAtTick(0)); // 1:1

        address[3] memory who = [user, attacker, lp];
        for (uint256 i; i < 3; i++) {
            t0.mint(who[i], 1e30);
            t1.mint(who[i], 1e30);
            vm.startPrank(who[i]);
            t0.approve(address(PERMIT2), type(uint256).max);
            t1.approve(address(PERMIT2), type(uint256).max);
            PERMIT2.approve(address(t0), address(POSM), type(uint160).max, type(uint48).max);
            PERMIT2.approve(address(t1), address(POSM), type(uint160).max, type(uint48).max);
            t0.approve(address(swapper), type(uint256).max);
            t1.approve(address(swapper), type(uint256).max);
            vm.stopPrank();
        }
        _mint(lp, -887_220, 887_220, 1e21); // background full-range liquidity
    }

    function _mint(address owner, int24 lo, int24 hi, uint256 liquidity) internal returns (uint256 id) {
        id = POSM.nextTokenId();
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, lo, hi, liquidity, type(uint128).max, type(uint128).max, owner, bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);
        vm.prank(owner);
        POSM.modifyLiquidities(abi.encode(abi.encodePacked(MINT_POSITION, SETTLE_PAIR), params), block.timestamp);
    }

    function _swap(address who, bool zeroForOne, int256 amount, uint160 limit) internal {
        vm.prank(who);
        swapper.swap(
            key, IPoolManager.SwapParams(zeroForOne, amount, limit), PoolSwapTest.TestSettings(false, false), bytes("")
        );
    }

    // 50 bps window around the 1:1 price the top-up was quoted at
    function _window() internal pure returns (uint160 lo, uint160 hi) {
        lo = TickMath.getSqrtPriceAtTick(-50);
        hi = TickMath.getSqrtPriceAtTick(50);
    }

    function test_encodeIncrease_revertsWhenPriceLeftTheWindow() public {
        uint256 id = _mint(user, -600, 600, 1e18);
        (uint160 lo, uint160 hi) = _window();

        // front-run: push the price to the top of the user's range
        _swap(attacker, false, -1e24, TickMath.getSqrtPriceAtTick(599));

        (uint160 sqrtPriceX96,,,) = _slot0();
        vm.expectRevert(abi.encodeWithSelector(PriceOutOfBounds.selector, sqrtPriceX96, lo, hi));
        helper.encodeIncrease(address(POSM), id, 100e18, 100e18, lo, hi, user);
    }

    function test_encodeIncrease_withinWindowAddsLiquidity() public {
        uint256 id = _mint(user, -600, 600, 1e18);
        (uint160 lo, uint160 hi) = _window();
        uint128 before = POSM.getPositionLiquidity(id);

        bytes memory data = helper.encodeIncrease(address(POSM), id, 100e18, 100e18, lo, hi, user);
        vm.prank(user);
        POSM.modifyLiquidities(data, block.timestamp + 900);

        assertGt(POSM.getPositionLiquidity(id), before, "liquidity not added");
    }

    // The increase nets the position's uncollected fees. Out of range with fees in the currency
    // it no longer needs, that currency's delta is a credit: SETTLE_PAIR reverted, CLOSE_CURRENCY
    // pays it to the caller.
    function test_encodeIncrease_paysFeeCreditInsteadOfReverting() public {
        uint256 id = _mint(user, -60, 60, 1e18);
        _swap(attacker, false, -1e15, TickMath.MAX_SQRT_PRICE - 1); // token1 in, in range: token1 fees accrue
        _swap(attacker, true, -1e24, TickMath.getSqrtPriceAtTick(-120)); // price leaves the range below

        uint256 t1Before = t1.balanceOf(user);
        uint128 before = POSM.getPositionLiquidity(id);

        bytes memory data = helper.encodeIncrease(address(POSM), id, 1e18, 1e18, 0, type(uint160).max, user);
        vm.prank(user);
        POSM.modifyLiquidities(data, block.timestamp + 900);

        assertGt(POSM.getPositionLiquidity(id), before, "liquidity not added");
        assertGt(t1.balanceOf(user), t1Before, "token1 fee credit not paid to the caller");
    }

    function _slot0() internal view returns (uint160, int24, uint24, uint24) {
        (bool ok, bytes memory ret) =
            address(POOL_MANAGER).staticcall(abi.encodeWithSignature("extsload(bytes32)", _slot0Key()));
        require(ok, "extsload");
        bytes32 word = abi.decode(ret, (bytes32));
        return (uint160(uint256(word)), 0, 0, 0);
    }

    function _slot0Key() internal view returns (bytes32) {
        // StateLibrary.POOLS_SLOT = 6; slot0 is the first word of the pool state
        return keccak256(abi.encodePacked(keccak256(abi.encode(key)), uint256(6)));
    }
}

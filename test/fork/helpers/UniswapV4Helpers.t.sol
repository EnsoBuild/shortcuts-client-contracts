// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniswapV4Helpers } from "../../../src/helpers/UniswapV4Helpers.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
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

        bytes memory data = helper.encodeIncrease(address(POSITION_MANAGER), TOKEN_ID, AMOUNT0_MAX, AMOUNT1_MAX, owner);

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
        bytes memory data =
            helper.encodeIncrease(address(POSITION_MANAGER), TOKEN_ID, AMOUNT0_MAX, AMOUNT1_MAX, address(this));
        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        POSITION_MANAGER.modifyLiquidities{ value: AMOUNT0_MAX }(data, block.timestamp + 900);
    }
}

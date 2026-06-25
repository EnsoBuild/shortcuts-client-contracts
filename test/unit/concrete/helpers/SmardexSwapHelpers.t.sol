// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { SmardexSwapHelpers } from "../../../../src/helpers/SmardexSwapHelpers.sol";
import { Test } from "forge-std/Test.sol";

contract SmardexSwapHelpersTest is Test {
    SmardexSwapHelpers public helpers;

    uint8 internal constant PAYMENT_TRANSFER_FROM = 2;

    address internal constant TOKEN_IN = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH
    address internal constant TOKEN_OUT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    address internal constant TO = 0x00000000000000000000000000000000DeaDBeef;

    function setUp() public {
        helpers = new SmardexSwapHelpers();
    }

    function test_encodeSwapInput_matchesRouterEncoding() public view {
        uint256 amountIn = 1 ether;
        uint256 minAmountOut = 0.9 ether;

        bytes memory swapInput = helpers.encodeSwapInput(TOKEN_IN, TOKEN_OUT, amountIn, minAmountOut, TO);

        address[] memory path = new address[](2);
        path[0] = TOKEN_IN;
        path[1] = TOKEN_OUT;
        bytes memory expected = abi.encode(uint128(amountIn), uint128(minAmountOut), path, TO, PAYMENT_TRANSFER_FROM);
        assertEq(swapInput, expected, "encoding must match the SmarDex swapInput layout");
    }

    function test_encodeSwapInput_decodesRoundTrip() public view {
        uint256 amountIn = 12_345;
        uint256 minAmountOut = 678;

        bytes memory swapInput = helpers.encodeSwapInput(TOKEN_IN, TOKEN_OUT, amountIn, minAmountOut, TO);

        (uint128 dAmountIn, uint128 dMinAmountOut, address[] memory dPath, address dTo, uint8 dPayment) =
            abi.decode(swapInput, (uint128, uint128, address[], address, uint8));

        assertEq(dAmountIn, uint128(amountIn), "amountIn");
        assertEq(dMinAmountOut, uint128(minAmountOut), "minAmountOut");
        assertEq(dPath.length, 2, "path length");
        assertEq(dPath[0], TOKEN_IN, "path[0]");
        assertEq(dPath[1], TOKEN_OUT, "path[1]");
        assertEq(dTo, TO, "to");
        assertEq(dPayment, PAYMENT_TRANSFER_FROM, "payment");
    }

    function test_encodeSwapInput_revertsOnAmountInOverflow() public {
        uint256 tooBig = uint256(type(uint128).max) + 1;
        vm.expectRevert();
        helpers.encodeSwapInput(TOKEN_IN, TOKEN_OUT, tooBig, 0, TO);
    }

    function test_encodeSwapInput_revertsOnMinAmountOutOverflow() public {
        uint256 tooBig = uint256(type(uint128).max) + 1;
        vm.expectRevert();
        helpers.encodeSwapInput(TOKEN_IN, TOKEN_OUT, 1 ether, tooBig, TO);
    }
}

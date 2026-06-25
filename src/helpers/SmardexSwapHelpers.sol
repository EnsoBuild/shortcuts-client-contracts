// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract SmardexSwapHelpers {
    using SafeCast for uint256;

    uint8 private constant PAYMENT_TRANSFER_FROM = 2;

    function encodeSwapInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    )
        external
        pure
        returns (bytes memory)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        return abi.encode(amountIn.toUint128(), minAmountOut.toUint128(), path, to, PAYMENT_TRANSFER_FROM);
    }
}

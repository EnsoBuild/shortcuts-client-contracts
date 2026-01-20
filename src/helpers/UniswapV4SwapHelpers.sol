// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";

contract UniswapV4SwapHelpers {
    using SafeERC20 for IERC20;

    IUniversalRouter public immutable UNIVERSAL_ROUTER;
    IPermit2 public immutable PERMIT2;

    error InvalidValue();
    error InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);

    constructor(IUniversalRouter universalRouter, IPermit2 permit2) {
        UNIVERSAL_ROUTER = universalRouter;
        PERMIT2 = permit2;
    }

    function swapExactInSingle(
        PoolKey calldata poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address receiver,
        bytes calldata hookData
    )
        public
        payable
        returns (uint256 amountOut)
    {
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);

        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountIn128 = uint128(amountIn);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 minAmountOut128 = uint128(minAmountOut);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: amountIn128,
                amountOutMinimum: minAmountOut128,
                hookData: hookData
            })
        );

        Currency currencyIn = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency currencyOut = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        params[1] = abi.encode(currencyIn, amountIn);
        params[2] = abi.encode(currencyOut, minAmountOut);

        if (currencyIn.isAddressZero()) {
            if (msg.value == 0) {
                revert InvalidValue();
            }
        } else {
            if (msg.value != 0) {
                revert InvalidValue();
            }
            address tokenIn = Currency.unwrap(currencyIn);
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            approveToken(tokenIn, amountIn);
        }

        inputs[0] = abi.encode(actions, params);
        UNIVERSAL_ROUTER.execute{ value: msg.value }(commands, inputs, deadline);

        address tokenOut = Currency.unwrap(currencyOut);
        amountOut = IERC20(tokenOut).balanceOf(address(this));
        if (amountOut < minAmountOut) {
            revert InsufficientOutputAmount(amountOut, minAmountOut);
        }
        IERC20(tokenOut).safeTransfer(receiver, amountOut);

        return amountOut;
    }

    function approveToken(address token, uint256 amount) private {
        IERC20(token).forceApprove(address(PERMIT2), amount);
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.approve(token, address(UNIVERSAL_ROUTER), uint160(amount), type(uint48).max);
    }
}

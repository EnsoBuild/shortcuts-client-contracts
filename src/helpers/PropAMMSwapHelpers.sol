// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPropAMM } from "../interfaces/IPropAMM.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title PropAMMSwapHelpers
/// @notice Swaps on a proprietary AMM (pAMM), falling back to a prebuilt swap when the pAMM can't fill.
/// @dev The fallback uses the `SwapHelpers` encoding. Never leave an allowance on this contract: the fallback is
/// an arbitrary call. Native ETH, fee-on-transfer and rebasing tokens are not supported.
contract PropAMMSwapHelpers is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    enum Outcome {
        PropAMMFilled,
        // No quote, or a quote below `minAmountOut`.
        PropAMMSkipped,
        // Reverted or paid less than its quote.
        PropAMMFailed
    }

    // Length word + selector.
    uint256 private constant _DATA_ARGS_OFFSET = 36;

    event PropAMMSwap(
        address indexed pamm,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address receiver,
        Outcome outcome,
        address fallbackTarget
    );

    error IdenticalTokens();
    error ZeroAmountIn();
    error InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);
    error InvalidReceiver();
    error InvalidFallbackTarget();
    error InvalidPointer(uint256 pointer);
    error AmountInMismatch(uint256 spent, uint256 amountIn);
    error NotSelf();

    /// @notice Swaps on `pamm`, or through the fallback if the pAMM is skipped or fails.
    /// @param pamm The pAMM to try first.
    /// @param tokenIn The token sold, pulled from `msg.sender`.
    /// @param tokenOut The token bought.
    /// @param amountIn The amount of `tokenIn` to sell.
    /// @param minAmountOut Minimum `tokenOut` for `receiver`, whichever venue fills.
    /// @param receiver The address that receives `tokenOut`.
    /// @param fallbackTarget The contract the fallback calls, such as a DEX router (`primary` in `SwapHelpers`).
    /// @param fallbackOperator The spender approved for `amountIn`, often the target itself (`operator` in
    /// `SwapHelpers`).
    /// @param fallbackData The fallback calldata, selector included. Its own minimum output can be zero.
    /// @param fallbackPointers Byte offsets in `fallbackData`, after the selector, where `amountIn` is written.
    /// @return amountOut The `tokenOut` `receiver` received.
    function swap(
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        address fallbackTarget,
        address fallbackOperator,
        bytes memory fallbackData,
        uint256[] memory fallbackPointers
    )
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (tokenIn == tokenOut) {
            revert IdenticalTokens();
        }
        if (amountIn == 0) {
            revert ZeroAmountIn();
        }
        if (receiver == address(0) || receiver == address(this)) {
            revert InvalidReceiver();
        }
        if (fallbackTarget == address(this)) {
            revert InvalidFallbackTarget();
        }

        uint256 outBalanceBefore = IERC20(tokenOut).balanceOf(receiver);

        Outcome outcome = _tryPropAMM(pamm, tokenIn, tokenOut, amountIn, minAmountOut, receiver);
        if (outcome != Outcome.PropAMMFilled) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            _executeFallback(
                tokenIn, tokenOut, amountIn, receiver, fallbackTarget, fallbackOperator, fallbackData, fallbackPointers
            );
        }

        amountOut = IERC20(tokenOut).balanceOf(receiver) - outBalanceBefore;
        if (amountOut < minAmountOut) {
            revert InsufficientOutputAmount(amountOut, minAmountOut);
        }

        // forge-lint: disable-next-line(reentrancy-events) `swap` is nonReentrant.
        emit PropAMMSwap(pamm, tokenIn, tokenOut, amountIn, amountOut, receiver, outcome, fallbackTarget);
    }

    /// @notice Pays and runs the pAMM. Self-only, so `swap` can roll it back with try/catch.
    /// @dev Reverts if `receiver` gets less than `minAmountOut`. Other parameters are as in `swap`.
    /// @param payer The account `tokenIn` is pulled from: `swap`'s caller.
    /// @param minAmountOut The pAMM's quote, which `receiver` must get.
    function executePropAMM(
        address payer,
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    )
        external
    {
        if (msg.sender != address(this)) {
            revert NotSelf();
        }

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);
        // forge-lint: disable-next-line(arbitrary-send-erc20) `payer` is always `swap`'s caller.
        IERC20(tokenIn).safeTransferFrom(payer, pamm, amountIn);
        // forge-lint: disable-next-line(unused-return) Measured at `receiver` instead.
        IPropAMM(pamm).swap(tokenIn, tokenOut, amountIn, minAmountOut, receiver, block.timestamp);

        uint256 received = IERC20(tokenOut).balanceOf(receiver) - balanceBefore;
        if (received < minAmountOut) {
            revert InsufficientOutputAmount(received, minAmountOut);
        }
    }

    /// @notice Writes `amount` into `data` at each pointer, like `SwapHelpers`, but bounds-checked.
    /// @param data Calldata, selector included. Modified in place.
    /// @param pointers Byte offsets in `data`, after the selector, of the words to overwrite.
    /// @param amount The value written at each pointer.
    /// @return The updated `data`.
    function insertAmount(
        bytes memory data,
        uint256[] memory pointers,
        uint256 amount
    )
        public
        pure
        returns (bytes memory)
    {
        uint256 length = pointers.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 pointer = pointers[i];
            if (data.length < _DATA_ARGS_OFFSET || pointer > data.length - _DATA_ARGS_OFFSET) {
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert InvalidPointer(pointer);
            }
            assembly ("memory-safe") {
                mstore(add(data, add(_DATA_ARGS_OFFSET, pointer)), amount)
            }
        }
        return data;
    }

    function _tryPropAMM(
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    )
        internal
        returns (Outcome)
    {
        uint256 pammQuote = _quotePropAMM(pamm, tokenIn, tokenOut, amountIn);
        if (pammQuote == 0 || pammQuote < minAmountOut) {
            return Outcome.PropAMMSkipped;
        }
        // The pAMM must deliver its quote.
        try this.executePropAMM(msg.sender, pamm, tokenIn, tokenOut, amountIn, pammQuote, receiver) {
            return Outcome.PropAMMFilled;
        } catch {
            return Outcome.PropAMMFailed;
        }
    }

    /// @dev Zero if the call fails or returns less than a word. Copies one word at most.
    function _quotePropAMM(
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        internal
        returns (uint256 amountOut)
    {
        bytes memory callData = abi.encodeCall(IPropAMM.quote, (tokenIn, tokenOut, amountIn));
        assembly ("memory-safe") {
            let success := call(gas(), pamm, 0, add(callData, 0x20), mload(callData), 0, 0)
            if and(success, gt(returndatasize(), 31)) {
                returndatacopy(0, 0, 0x20)
                amountOut := mload(0)
            }
        }
    }

    /// @dev Must spend exactly `amountIn`. Forwards any `tokenOut` it receives to `receiver`.
    function _executeFallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        address target,
        address operator,
        bytes memory data,
        uint256[] memory pointers
    )
        internal
    {
        if (pointers.length != 0) {
            insertAmount(data, pointers, amountIn);
        }
        uint256 inBalanceBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 outBalanceBefore = IERC20(tokenOut).balanceOf(address(this));

        IERC20(tokenIn).forceApprove(operator, amountIn);
        (bool success, bytes memory response) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(response, 0x20), mload(response))
            }
        }
        IERC20(tokenIn).forceApprove(operator, 0);

        uint256 inBalanceAfter = IERC20(tokenIn).balanceOf(address(this));
        uint256 spent = inBalanceBefore > inBalanceAfter ? inBalanceBefore - inBalanceAfter : 0;
        if (spent != amountIn) {
            revert AmountInMismatch(spent, amountIn);
        }

        uint256 received = IERC20(tokenOut).balanceOf(address(this)) - outBalanceBefore;
        if (received != 0) {
            IERC20(tokenOut).safeTransfer(receiver, received);
        }
    }
}

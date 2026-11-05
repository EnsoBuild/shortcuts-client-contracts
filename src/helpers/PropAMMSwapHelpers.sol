// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPropAMM } from "../interfaces/IPropAMM.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface ICurveCoins {
    function coins(uint256 i) external view returns (address);
}

interface ICurveLegacyCoins {
    function coins(int128 i) external view returns (address);
}

interface ICurveInt128Pool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external;
}

interface ICurveUint256Pool {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) external;
}

/// @title PropAMMSwapHelpers
/// @notice Swaps through a proprietary AMM (pAMM) with a public-pool fallback in the same call.
/// @dev Tries the pAMM when it quotes at least `minAmountOut`. A pAMM price is only fresh in the block it was
/// quoted for, so when the pAMM cannot quote, quotes too little or fails to fill, a caller-chosen public pool
/// fills instead. Pulls `amountIn` from `msg.sender` and holds no funds between transactions. Native ETH,
/// fee-on-transfer and rebasing tokens are not supported.
contract PropAMMSwapHelpers is ReentrancyGuardTransient, IUnlockCallback {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Protocols a fallback pool can belong to. `fallbackData` is the ABI encoding of:
    /// - UniswapV3: `(address pool)`, any fork paying through `uniswapV3SwapCallback` or `pancakeV3SwapCallback`
    /// - UniswapV4: `(uint24 fee, int24 tickSpacing, address hooks, bytes hookData)`, ERC20 pools only
    /// - Curve: `(address pool, bool int128Indices, uint8 i, uint8 j)`
    /// A UniswapV3 or Curve pool that does not trade `tokenIn` for `tokenOut` reverts `FallbackTokenMismatch`.
    enum FallbackProtocol {
        UniswapV3,
        UniswapV4,
        Curve
    }

    /// @notice Which venue filled the swap, and why.
    enum Outcome {
        // The pAMM filled.
        PropAMMFilled,
        // The pAMM could not quote, or quoted less than `minAmountOut`, so the fallback filled.
        PropAMMSkipped,
        // The pAMM reverted or paid less than `minAmountOut`, so the fallback filled.
        PropAMMFailed
    }

    struct UniswapV4Swap {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address receiver;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
    }

    // Uniswap V3 callback context: the pool allowed to call back and what it may be paid.
    // keccak256("PropAMMSwapHelpers.callbackPool")
    bytes32 private constant _CALLBACK_POOL_SLOT = 0x417d8cb7d95d92b48dbe2c1f9b9869cad5dbbadf56c9cac6caeb17bf68b735db;
    // keccak256("PropAMMSwapHelpers.callbackToken")
    bytes32 private constant _CALLBACK_TOKEN_SLOT = 0xcbb9778f15709ac081bdff2bd84c2220bb00879014084f96fbfb2f5ef0862994;
    // keccak256("PropAMMSwapHelpers.callbackAmount")
    bytes32 private constant _CALLBACK_AMOUNT_SLOT = 0xab63d39e5dde0dd810f7e22cff3ba64d547afce77048e8170f33f2c72508a4a1;

    /// @notice Uniswap V4's PoolManager, or zero on a chain without it (V4 fallbacks then revert).
    IPoolManager public immutable POOL_MANAGER;

    event PropAMMSwap(
        address indexed pamm,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address receiver,
        Outcome outcome,
        FallbackProtocol fallbackProtocol
    );

    error IdenticalTokens();
    error ZeroAmountIn();
    error InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);
    error InvalidCallback();
    error InvalidReceiver();
    error AmountInMismatch(uint256 requested, uint256 amountIn);
    error FallbackTokenMismatch();
    error NotSelf();
    error ProtocolUnavailable(FallbackProtocol protocol);

    constructor(IPoolManager poolManager) {
        POOL_MANAGER = poolManager;
    }

    /// @notice Swaps `amountIn` of `tokenIn` for `tokenOut` on `pamm`, or on the fallback pool when the pAMM is
    /// skipped or fails.
    /// @param minAmountOut The minimum `tokenOut` `receiver` must get, whichever venue fills.
    /// @param fallbackData The fallback pool, encoded as `FallbackProtocol` documents.
    /// @return amountOut The `tokenOut` `receiver` received.
    function swap(
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        FallbackProtocol fallbackProtocol,
        bytes calldata fallbackData
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

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 outBalanceBefore = IERC20(tokenOut).balanceOf(receiver);

        Outcome outcome =
            _swap(pamm, tokenIn, tokenOut, amountIn, minAmountOut, receiver, fallbackProtocol, fallbackData);

        amountOut = IERC20(tokenOut).balanceOf(receiver) - outBalanceBefore;
        if (amountOut < minAmountOut) {
            revert InsufficientOutputAmount(amountOut, minAmountOut);
        }

        // `swap` is nonReentrant, so no call can reorder or fake this event.
        // forge-lint: disable-next-line(reentrancy-events)
        emit PropAMMSwap(pamm, tokenIn, tokenOut, amountIn, amountOut, receiver, outcome, fallbackProtocol);
    }

    /// @notice Runs the pAMM swap. Only callable by this contract, so `swap` can roll it back with try/catch.
    /// @dev Reverts unless `receiver` gets at least `minAmountOut`, so an underpaying pAMM falls through too.
    function executePropAMM(
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
        IERC20(tokenIn).safeTransfer(pamm, amountIn);
        // The output is measured at `receiver` below, not taken from the pAMM's return value.
        // forge-lint: disable-next-line(unused-return)
        IPropAMM(pamm).swap(tokenIn, tokenOut, amountIn, minAmountOut, receiver, block.timestamp);

        uint256 received = IERC20(tokenOut).balanceOf(receiver) - balanceBefore;
        if (received < minAmountOut) {
            revert InsufficientOutputAmount(received, minAmountOut);
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        _uniswapV3Callback(amount0Delta, amount1Delta);
    }

    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        _uniswapV3Callback(amount0Delta, amount1Delta);
    }

    /// @notice Runs a Uniswap V4 fallback swap inside the PoolManager's lock.
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) {
            revert InvalidCallback();
        }

        UniswapV4Swap memory v4Swap = abi.decode(rawData, (UniswapV4Swap));
        bool zeroForOne = v4Swap.tokenIn < v4Swap.tokenOut;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(zeroForOne ? v4Swap.tokenIn : v4Swap.tokenOut),
            currency1: Currency.wrap(zeroForOne ? v4Swap.tokenOut : v4Swap.tokenIn),
            fee: v4Swap.fee,
            tickSpacing: v4Swap.tickSpacing,
            hooks: IHooks(v4Swap.hooks)
        });

        BalanceDelta delta = POOL_MANAGER.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                // Negative means exact input.
                amountSpecified: -v4Swap.amountIn.toInt256(),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            v4Swap.hookData
        );

        (int128 inDelta, int128 outDelta) =
            zeroForOne ? (delta.amount0(), delta.amount1()) : (delta.amount1(), delta.amount0());
        // The swap owes the pool a non-positive `inDelta` and is owed a non-negative `outDelta`; the casts revert
        // on a hook that flips either sign.
        uint256 amountPaid = SafeCast.toUint256(-int256(inDelta));
        uint256 amountOut = SafeCast.toUint256(int256(outDelta));

        // The pool must take exactly `amountIn`: no partial fills, no overcharge.
        if (amountPaid != v4Swap.amountIn) {
            revert AmountInMismatch(amountPaid, v4Swap.amountIn);
        }

        POOL_MANAGER.sync(Currency.wrap(v4Swap.tokenIn));
        IERC20(v4Swap.tokenIn).safeTransfer(address(POOL_MANAGER), amountPaid);
        // `settle` returns the amount just transferred.
        // forge-lint: disable-next-line(unused-return)
        POOL_MANAGER.settle();
        if (amountOut != 0) {
            POOL_MANAGER.take(Currency.wrap(v4Swap.tokenOut), v4Swap.receiver, amountOut);
        }
        return "";
    }

    function _swap(
        address pamm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        FallbackProtocol fallbackProtocol,
        bytes calldata fallbackData
    )
        internal
        returns (Outcome outcome)
    {
        // The fallback is never quoted: the pAMM is tried whenever it quotes at least `minAmountOut`.
        uint256 pammQuote = _quotePropAMM(pamm, tokenIn, tokenOut, amountIn);
        if (pammQuote == 0 || pammQuote < minAmountOut) {
            outcome = Outcome.PropAMMSkipped;
        } else {
            // At least 1, so a pAMM that pays nothing falls through even when `minAmountOut` is zero.
            uint256 pammMinAmountOut = minAmountOut == 0 ? 1 : minAmountOut;
            try this.executePropAMM(pamm, tokenIn, tokenOut, amountIn, pammMinAmountOut, receiver) {
                return Outcome.PropAMMFilled;
            } catch {
                outcome = Outcome.PropAMMFailed;
            }
        }

        // Runs in this frame: a fallback that reverts reverts the whole swap.
        _executeFallback(fallbackProtocol, tokenIn, tokenOut, amountIn, receiver, fallbackData);
    }

    /// @dev Zero when the pAMM reverts, has no code or returns less than a word. Copies at most one word of
    /// return data, so a pAMM cannot make this frame pay for a large revert reason.
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

    function _executeFallback(
        FallbackProtocol protocol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        bytes calldata data
    )
        internal
    {
        if (protocol == FallbackProtocol.UniswapV3) {
            _swapUniswapV3(tokenIn, tokenOut, amountIn, receiver, data);
        } else if (protocol == FallbackProtocol.UniswapV4) {
            _swapUniswapV4(tokenIn, tokenOut, amountIn, receiver, data);
        } else {
            _swapCurve(tokenIn, tokenOut, amountIn, receiver, data);
        }
    }

    /// @dev Exact input of all of `amountIn`, paid in `_uniswapV3Callback`.
    function _swapUniswapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        bytes calldata data
    )
        internal
    {
        address pool = abi.decode(data, (address));
        bool zeroForOne = tokenIn < tokenOut;
        (address token0, address token1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        if (IUniswapV3Pool(pool).token0() != token0 || IUniswapV3Pool(pool).token1() != token1) {
            revert FallbackTokenMismatch();
        }

        _setCallbackContext(pool, tokenIn, amountIn);
        // `swap` measures the output at `receiver`; the callback checks the input.
        // forge-lint: disable-next-item(unused-return)
        IUniswapV3Pool(pool)
            .swap(
                receiver,
                zeroForOne,
                amountIn.toInt256(),
                zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
                ""
            );
        _setCallbackContext(address(0), address(0), 0);
    }

    /// @dev Pays only the pool `_swapUniswapV3` called, once, from its context; the callback `data` is ignored.
    function _uniswapV3Callback(int256 amount0Delta, int256 amount1Delta) internal {
        (address pool, address tokenIn, uint256 amountIn) = _callbackContext();
        if (msg.sender != pool) {
            revert InvalidCallback();
        }
        _setCallbackContext(address(0), address(0), 0);

        // The positive delta is what the pool is owed. It must be exactly `amountIn`: no partial fills, no
        // overcharge.
        uint256 amountPaid = SafeCast.toUint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        if (amountPaid != amountIn) {
            revert AmountInMismatch(amountPaid, amountIn);
        }
        IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
    }

    function _swapUniswapV4(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        bytes calldata data
    )
        internal
    {
        if (address(POOL_MANAGER) == address(0)) {
            revert ProtocolUnavailable(FallbackProtocol.UniswapV4);
        }
        (uint24 fee, int24 tickSpacing, address hooks, bytes memory hookData) =
            abi.decode(data, (uint24, int24, address, bytes));

        // `unlockCallback` returns nothing to read.
        // forge-lint: disable-next-item(unused-return)
        POOL_MANAGER.unlock(
            abi.encode(
                UniswapV4Swap({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    receiver: receiver,
                    fee: fee,
                    tickSpacing: tickSpacing,
                    hooks: hooks,
                    hookData: hookData
                })
            )
        );
    }

    /// @dev Curve pays the caller, so the output is forwarded. The approval is cleared after the exchange.
    function _swapCurve(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        bytes calldata data
    )
        internal
    {
        (address pool, bool int128Indices, uint8 i, uint8 j) = abi.decode(data, (address, bool, uint8, uint8));
        if (_curveCoin(pool, i) != tokenIn || _curveCoin(pool, j) != tokenOut) {
            revert FallbackTokenMismatch();
        }
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        IERC20(tokenIn).forceApprove(pool, amountIn);
        if (int128Indices) {
            ICurveInt128Pool(pool).exchange(int128(uint128(i)), int128(uint128(j)), amountIn, 0);
        } else {
            ICurveUint256Pool(pool).exchange(i, j, amountIn, 0);
        }
        IERC20(tokenIn).forceApprove(pool, 0);

        IERC20(tokenOut).safeTransfer(receiver, IERC20(tokenOut).balanceOf(address(this)) - balanceBefore);
    }

    /// @dev `coins` is indexed with `uint256` on most pools and `int128` on pre-2021 ones, independently of how
    /// `exchange` indexes coins (3pool exchanges with `int128` but reads `coins` with `uint256`).
    function _curveCoin(address pool, uint8 index) internal view returns (address) {
        try ICurveCoins(pool).coins(index) returns (address coin) {
            return coin;
        } catch {
            return ICurveLegacyCoins(pool).coins(int128(uint128(index)));
        }
    }

    function _callbackContext() internal view returns (address pool, address token, uint256 amount) {
        assembly ("memory-safe") {
            pool := tload(_CALLBACK_POOL_SLOT)
            token := tload(_CALLBACK_TOKEN_SLOT)
            amount := tload(_CALLBACK_AMOUNT_SLOT)
        }
    }

    function _setCallbackContext(address pool, address token, uint256 amount) internal {
        assembly ("memory-safe") {
            tstore(_CALLBACK_POOL_SLOT, pool)
            tstore(_CALLBACK_TOKEN_SLOT, token)
            tstore(_CALLBACK_AMOUNT_SLOT, amount)
        }
    }
}

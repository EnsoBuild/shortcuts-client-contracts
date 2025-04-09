// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

error ValueExceedsUint160Range();

contract UniswapV4Helpers {
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function uint256ToUint128(uint256 input) public pure returns (uint128) {
        if (input > type(uint128).max) revert ValueExceedsUint160Range();

        return uint128(input);
    }

    function uint256ToUint160(uint256 input) public pure returns (uint160) {
        if (input > type(uint160).max) revert ValueExceedsUint160Range();

        return uint160(input);
    }

    function getPoolKey(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    )
        public
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });
    }

    function getLiquidityForAmounts(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    )
        public
        view
        returns (uint128)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());

        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    function encodeMintWithHooks(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        address hooks
    )
        public
        pure
        returns (bytes memory)
    {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);

        {
            params[0] = abi.encode(
                getPoolKey(currency0, currency1, fee, tickSpacing, hooks),
                tickLower,
                tickUpper,
                liquidity,
                uint256ToUint128(amount0Max),
                uint256ToUint128(amount1Max),
                recipient,
                bytes("")
            );
        }
        params[1] = abi.encode(currency0, currency1);

        return abi.encode(actions, params);
    }

    function encodeMint(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient
    )
        external
        pure
        returns (bytes memory)
    {
        return encodeMintWithHooks(
            currency0,
            currency1,
            fee,
            tickSpacing,
            tickLower,
            tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            recipient,
            address(0)
        );
    }

    function encodeMintFromDeltasWithHooks(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        address hooks
    )
        public
        view
        returns (bytes memory)
    {
        uint128 liquidity = getLiquidityForAmounts(
            getPoolKey(currency0, currency1, fee, tickSpacing, hooks), tickLower, tickUpper, amount0Max, amount1Max
        );

        return encodeMintWithHooks(
            currency0,
            currency1,
            fee,
            tickSpacing,
            tickLower,
            tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            recipient,
            hooks
        );
    }

    function encodeMintFromDeltas(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient
    )
        external
        view
        returns (bytes memory)
    {
        return encodeMintFromDeltasWithHooks(
            currency0, currency1, fee, tickSpacing, tickLower, tickUpper, amount0Max, amount1Max, recipient, address(0)
        );
    }
}

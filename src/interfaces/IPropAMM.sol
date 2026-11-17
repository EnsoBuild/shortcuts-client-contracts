// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPropAMM
/// @notice The standard interface proprietary AMMs (pAMMs) expose to be routable, as published by LambdaClass
/// (https://github.com/lambdaclass/propamm-router-contracts, MIT) and used by Titan Builder's pAMM venues.
/// @dev `swap` is push-payment: the caller transfers `amountIn` of `tokenIn` to the pAMM before calling it.
interface IPropAMM {
    struct TokenPair {
        address token0;
        address token1;
    }

    event Swapped(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    /// @notice Whether a swap of `tokenIn` for `tokenOut` would succeed in the current block.
    function isActive(address tokenIn, address tokenOut) external view returns (bool active);

    /// @notice Every pair the pAMM supports, active or not.
    function getPairs() external view returns (TokenPair[] memory pairs);

    /// @notice The `tokenOut` a swap of `amountIn` would deliver. Reverts when the pair is inactive and needs no
    /// balance or allowance from the caller.
    function quote(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);

    /// @notice Swaps the `amountIn` of `tokenIn` already transferred to the pAMM, delivering at least
    /// `minAmountOut` of `tokenOut` to `recipient`.
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    )
        external
        returns (uint256 amountOut);
}

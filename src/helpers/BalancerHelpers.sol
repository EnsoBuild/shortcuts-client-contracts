// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBalancerVault {
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

interface IBalancerPool {
    function totalSupply() external view returns (uint256);
}

/**
 * @notice Helper contract to encode Balancer userData
 */
contract BalancerHelpers {
    uint256 public constant VERSION = 4;

    function encodeDataForJoinKindOne(
        uint256 joinKind,
        uint256[] memory amounts,
        uint256 minimumBPT
    )
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(joinKind, amounts, minimumBPT);
    }

    function encodeDataForExitKindZero(
        uint256 exitKind,
        uint256 amount,
        uint256 tokenIndex
    )
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(exitKind, amount, tokenIndex);
    }

    function encodeDataForJoinKindThree(uint256 joinKind, uint256 bptAmountOut) public pure returns (bytes memory) {
        return abi.encode(joinKind, bptAmountOut);
    }

    function computeProportionalBptOut(
        bytes32 poolId,
        address vault,
        address pool,
        uint256[] calldata amounts
    )
        external
        view
        returns (uint256 bptAmountOut)
    {
        (, uint256[] memory balances,) = IBalancerVault(vault).getPoolTokens(poolId);
        uint256 totalSupply = IBalancerPool(pool).totalSupply();

        bptAmountOut = type(uint256).max;
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0 && balances[i] > 0) {
                uint256 bptForToken = amounts[i] * totalSupply / balances[i];
                if (bptForToken < bptAmountOut) {
                    bptAmountOut = bptForToken;
                }
            }
        }

        if (bptAmountOut == type(uint256).max) {
            bptAmountOut = 0;
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMaverickV2Pool {
    struct AddLiquidityParams {
        uint8 kind;
        int32[] ticks;
        uint128[] amounts;
    }
}

interface IMaverickV2PoolLens {
    struct AddParamsSpecification {
        uint256 slippageFactorD18;
        uint256 numberOfPriceBreaksPerSide;
        uint256 targetAmount;
        bool targetIsA;
    }

    struct TickDeltas {
        uint256 deltaAOut;
        uint256 deltaBOut;
        uint256[] deltaAs;
        uint256[] deltaBs;
    }

    function getAddLiquidityParamsForBoostedPosition(
        address boostedPosition,
        AddParamsSpecification memory addSpec
    )
        external
        view
        returns (
            bytes memory packedSqrtPriceBreaks,
            bytes[] memory packedArgs,
            uint88[] memory sqrtPriceBreaks,
            IMaverickV2Pool.AddLiquidityParams[] memory addParams,
            IMaverickV2PoolLens.TickDeltas[] memory tickDeltas
        );
}

interface IMaverickV2LiquidityManager {
    function addLiquidityAndMintBoostedPosition(
        address recipient,
        address boostedPosition,
        bytes memory packedSqrtPriceBreaks,
        bytes[] memory packedArgs
    )
        external
        payable
        returns (uint256 mintedLpAmount, uint256 tokenAAmount, uint256 tokenBAmount);
}

/**
 * @notice Helper contract to encode Maverick boosted positions
 */
contract MaverickV2Helpers {
    uint256 public constant VERSION = 1;

    function encodeAddLiquidityAndMintBoostedPosition(
        uint256 amountA,
        address boostedPosition,
        address lens,
        address receiver
    )
        public
        view
        returns (bytes memory)
    {
        IMaverickV2PoolLens.AddParamsSpecification memory addSpec = IMaverickV2PoolLens.AddParamsSpecification({
            slippageFactorD18: 0,
            numberOfPriceBreaksPerSide: 0,
            targetAmount: amountA,
            targetIsA: true
        });

        (bytes memory packedSqrtPriceBreaks, bytes[] memory packedArgs,,,) =
            IMaverickV2PoolLens(lens).getAddLiquidityParamsForBoostedPosition(boostedPosition, addSpec);

        return abi.encodeWithSelector(
            IMaverickV2LiquidityManager.addLiquidityAndMintBoostedPosition.selector,
            receiver,
            boostedPosition,
            packedSqrtPriceBreaks,
            packedArgs
        );
    }
}

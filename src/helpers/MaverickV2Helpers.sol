// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

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
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 1;
    uint256 BIP = 10000;

    error InvalidBIP(uint256 amount);

    function addLiquidityAndMintBoostedPosition(
        uint256 amountA,
        uint256 amountB,
        IERC20 tokenA,
        IERC20 tokenB,
        bool targetIsA,
        uint256 targetBipModifier,
        address boostedPosition,
        address manager,
        address lens,
        address receiver,
        address refund
    )
        external
    {
        // get funds from msg.sender
        tokenA.safeTransferFrom(msg.sender, address(this), amountA);
        tokenB.safeTransferFrom(msg.sender, address(this), amountB);
        // get target amount
        uint256 targetAmount = targetIsA
            ? amountA
            : amountB;
        // conditionally modify target amount
        if (targetBipModifier > 0) {
            if (targetBipModifier > BIP - 1) revert InvalidBIP(targetBipModifier);
            targetAmount = (targetAmount * (BIP - targetBipModifier)) / BIP;
        }
        // get params
        IMaverickV2PoolLens.AddParamsSpecification memory addSpec = IMaverickV2PoolLens.AddParamsSpecification({
            slippageFactorD18: 0,
            numberOfPriceBreaksPerSide: 0,
            targetAmount: targetAmount,
            targetIsA: targetIsA
        });
        (bytes memory packedSqrtPriceBreaks, bytes[] memory packedArgs,,,) =
            IMaverickV2PoolLens(lens).getAddLiquidityParamsForBoostedPosition(boostedPosition, addSpec);
        // approve manager to spend funds
        tokenA.forceApprove(manager, amountA);
        tokenB.forceApprove(manager, amountB);
        // add liquidity (boostedPosition will be sent to receiver)
        IMaverickV2LiquidityManager(manager).addLiquidityAndMintBoostedPosition(
            receiver,
            boostedPosition,
            packedSqrtPriceBreaks,
            packedArgs
        );
        // refund remaining
        tokenA.safeTransfer(refund, tokenA.balanceOf(address(this)));
        tokenB.safeTransfer(refund, tokenB.balanceOf(address(this)));
    }
}

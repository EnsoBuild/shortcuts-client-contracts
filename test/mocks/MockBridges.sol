// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IAcrossSpokePool } from "../../src/interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../../src/interfaces/bridges/ITokenMessengerV2.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// Records depositForBurn and pulls the burned amount, as TokenMessengerV2 does.
contract MockTokenMessengerV2 is ITokenMessengerV2 {
    struct Burn {
        uint256 amount;
        uint32 destinationDomain;
        bytes32 mintRecipient;
        address burnToken;
        bytes32 destinationCaller;
        uint256 maxFee;
        uint32 minFinalityThreshold;
    }

    Burn public last;
    uint256 public burns;

    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    )
        external
    {
        IERC20(burnToken).transferFrom(msg.sender, address(this), amount);
        last =
            Burn(amount, destinationDomain, mintRecipient, burnToken, destinationCaller, maxFee, minFinalityThreshold);
        ++burns;
    }
}

/// Records deposit and pulls the input, as the Across SpokePool does, including its quote-time and
/// fill-deadline buffers.
contract MockAcrossSpokePool is IAcrossSpokePool {
    struct Deposit {
        bytes32 depositor;
        bytes32 recipient;
        bytes32 inputToken;
        bytes32 outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint256 destinationChainId;
        bytes32 exclusiveRelayer;
        uint32 quoteTimestamp;
        uint32 fillDeadline;
        uint32 exclusivityParameter;
        bytes message;
    }

    uint32 public constant depositQuoteTimeBuffer = 3600;
    uint32 public constant fillDeadlineBuffer = 6 hours;

    Deposit private s_last;
    uint256 public deposits;

    error InvalidQuoteTimestamp();
    error InvalidFillDeadline();
    error MsgValueDoesNotMatchInputAmount();

    function deposit(
        bytes32 depositor,
        bytes32 recipient,
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        bytes32 exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter,
        bytes calldata message
    )
        external
        payable
    {
        if (block.timestamp < quoteTimestamp || block.timestamp - quoteTimestamp > depositQuoteTimeBuffer) {
            revert InvalidQuoteTimestamp();
        }
        if (fillDeadline > block.timestamp + fillDeadlineBuffer) {
            revert InvalidFillDeadline();
        }
        if (msg.value != 0) {
            revert MsgValueDoesNotMatchInputAmount();
        }
        IERC20(address(uint160(uint256(inputToken)))).transferFrom(msg.sender, address(this), inputAmount);
        s_last = Deposit(
            depositor,
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityParameter,
            message
        );
        ++deposits;
    }

    function last() external view returns (Deposit memory) {
        return s_last;
    }
}

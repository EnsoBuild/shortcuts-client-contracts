// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IL1GatewayRouter } from "./interfaces/arbitrum/IL1GatewayRouter.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EnsoArbitrumDepositor
/// @author Enso
/// @notice Deposits ERC-20 tokens into Arbitrum's canonical token bridge on behalf of a receiver
/// @dev This contract is the retryable ticket beneficiary. Its L2 alias never sends a message, so nobody can cancel
///      a deposit.
contract EnsoArbitrumDepositor is Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error WrongMsgValue(uint256 expected, uint256 actual);
    error UnexpectedGateway(address expected, address actual);
    error AmountMismatch(uint256 expected, uint256 actual);
    error BalanceChanged(uint256 balanceBefore, uint256 balanceAfter);
    error RenounceOwnershipDisabled();

    constructor(address owner_) Ownable(owner_) { }

    /// @notice Pulls tokens from the caller and deposits them to `to` on the router's child chain
    /// @dev msg.value must equal maxSubmissionCost plus maxGas times gasPriceBid. `refundTo` is aliased on L2 when it
    ///      has code on L1. The deposit must leave this contract's token balance unchanged.
    function deposit(
        IL1GatewayRouter router,
        address gateway,
        IERC20 token,
        uint256 amount,
        address to,
        address refundTo,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    )
        external
        payable
    {
        if (to == address(0) || refundTo == address(0)) {
            revert ZeroAddress();
        }

        uint256 expectedValue = maxSubmissionCost + maxGas * gasPriceBid;
        if (msg.value != expectedValue) {
            revert WrongMsgValue(expectedValue, msg.value);
        }

        address routedGateway = router.getGateway(address(token));
        if (routedGateway == address(0) || routedGateway != gateway) {
            revert UnexpectedGateway(gateway, routedGateway);
        }

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != amount) {
            revert AmountMismatch(amount, received);
        }

        token.forceApprove(gateway, amount);

        bytes memory gatewayData = abi.encode(maxSubmissionCost, bytes(""));
        router.outboundTransferCustomRefund{ value: msg.value }(
            address(token), refundTo, to, amount, maxGas, gasPriceBid, gatewayData
        );

        if (token.allowance(address(this), gateway) != 0) {
            token.forceApprove(gateway, 0);
        }

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter != balanceBefore) {
            revert BalanceChanged(balanceBefore, balanceAfter);
        }
    }

    /// @notice Returns tokens held by this contract, such as deposits bounced by a custom gateway
    function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    function renounceOwnership() public pure override {
        revert RenounceOwnershipDisabled();
    }
}

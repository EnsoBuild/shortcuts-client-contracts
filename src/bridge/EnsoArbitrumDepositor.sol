// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IL1GatewayRouter } from "./interfaces/arbitrum/IL1GatewayRouter.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EnsoArbitrumDepositor
/// @author Enso
/// @notice Deposits ERC-20 tokens into Arbitrum's canonical token bridge on behalf of a receiver, through an
///         L1 gateway router.
/// @dev The gateway makes its caller the beneficiary of the retryable ticket, which is the only address that can
///      cancel it. This contract is that caller. It never calls an inbox, so its L2 alias never sends a message and
///      nobody can cancel a deposit. Redeem and keepalive stay permissionless on L2.
///      Custom gateways bounce deposits whose L2 token is missing or mismatched back to this contract, and the owner
///      returns them to the receiver with {withdraw}.
contract EnsoArbitrumDepositor is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the receiver or the refund address is the zero address
    error ZeroAddress();

    /// @notice Thrown when msg.value does not equal maxSubmissionCost plus maxGas times gasPriceBid
    /// @param expected The required msg.value
    /// @param actual The msg.value sent
    error WrongMsgValue(uint256 expected, uint256 actual);

    /// @notice Thrown when the router does not route the token to the expected gateway, including when it has no
    ///         gateway for the token
    /// @param expected The gateway the caller expects
    /// @param actual The gateway the router returns
    error UnexpectedGateway(address expected, address actual);

    /// @notice Thrown when the contract receives a different amount than requested, for example from a
    ///         fee-on-transfer token
    /// @param expected The requested amount
    /// @param actual The amount received
    error AmountMismatch(uint256 expected, uint256 actual);

    /// @notice Thrown when a deposit changes the contract's token balance, which protects tokens held for the owner
    /// @param balanceBefore The token balance before the deposit
    /// @param balanceAfter The token balance after the deposit
    error BalanceChanged(uint256 balanceBefore, uint256 balanceAfter);

    /// @notice Thrown when renouncing ownership, which would lock held tokens forever
    error RenounceOwnershipDisabled();

    /// @param owner_ The owner that withdraws bounced deposits
    constructor(address owner_) Ownable(owner_) { }

    /// @notice Pulls tokens from the caller and deposits them to `to` on the router's child chain
    /// @dev msg.value pays for the retryable ticket and must equal maxSubmissionCost plus maxGas times gasPriceBid.
    ///      `refundTo` receives the excess fee refund on L2, aliased when it has code on L1.
    ///      The gateway is only approved for the amount just pulled from the caller, the approval is reset afterwards,
    ///      and the deposit must leave the contract's token balance unchanged, so tokens already held by this
    ///      contract cannot be moved by a deposit.
    /// @param router The L1 gateway router of the child chain
    /// @param gateway The gateway the router must route the token to
    /// @param token The L1 token to deposit
    /// @param amount The amount of tokens to pull from the caller and deposit
    /// @param to The receiver on L2
    /// @param refundTo The receiver of the excess fee refund on L2
    /// @param maxGas The L2 gas limit of the retryable ticket
    /// @param gasPriceBid The L2 max fee per gas of the retryable ticket
    /// @param maxSubmissionCost The max submission cost of the retryable ticket
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

    /// @notice Sends tokens held by this contract, such as bounced deposits, to `to`
    /// @param token The token to send
    /// @param to The recipient
    /// @param amount The amount to send
    function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    /// @notice Always reverts, so held tokens always have an owner who can return them
    function renounceOwnership() public pure override {
        revert RenounceOwnershipDisabled();
    }
}

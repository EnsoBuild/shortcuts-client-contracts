// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IIntentGuardian, Level, Obligation, Status } from "../interfaces/IIntentGuardian.sol";
import { IAcrossSpokePool } from "../interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../interfaces/bridges/ITokenMessengerV2.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BridgeGuardian
/// @notice A FORWARD guardian over CCTP and Across. It builds each bridge call from the obligation
///         itself, so the destination, recipient, delivered asset and minimum are the intent's, never
///         the keeper's. Funds pass through within `accept` and nothing rests here. Delivery then
///         relies on the bridge alone: there is no bond and no settlement.
/// @dev Non-upgradeable, with no admin. One deployment per chain, configured at construction.
contract BridgeGuardian is IIntentGuardian {
    using SafeERC20 for IERC20;

    bytes32 public constant CCTP = keccak256("cctp");
    bytes32 public constant ACROSS = keccak256("across");

    /// A CCTP destination: its Circle domain and the native USDC delivered there.
    struct CctpDestination {
        uint256 chainId;
        uint32 domain;
        address usdc;
    }

    struct Domain {
        uint32 domain;
        address usdc;
    }

    /// CCTP on this chain; zero when CCTP isn't supported here.
    ITokenMessengerV2 public immutable tokenMessenger;
    address public immutable usdc;
    /// Across on this chain; zero when Across isn't supported here.
    IAcrossSpokePool public immutable spokePool;

    mapping(uint256 chainId => Domain destination) public cctpDestinations;
    mapping(bytes32 receipt => Status status) private s_status;
    uint256 private s_accepted;

    error UnsupportedToken();
    error UnsupportedMethod(bytes32 method);
    error MethodMismatch(bytes32 committed, bytes32 chosen);
    error UnsupportedDestination(uint256 chainId);
    error WrongDeliveredToken(address expected, address committed);
    error BelowMinimum(uint256 delivered, uint256 minAmount);
    error DeadlineTooLate(uint32 fillDeadline, uint64 deadline);
    error RefundToCaller();
    error Unsupported();

    constructor(
        ITokenMessengerV2 tokenMessenger_,
        address usdc_,
        CctpDestination[] memory destinations,
        IAcrossSpokePool spokePool_
    ) {
        tokenMessenger = tokenMessenger_;
        usdc = usdc_;
        spokePool = spokePool_;
        for (uint256 i; i < destinations.length; ++i) {
            CctpDestination memory d = destinations[i];
            cctpDestinations[d.chainId] = Domain({ domain: d.domain, usdc: d.usdc });
        }
    }

    function level() external pure returns (Level) {
        return Level.FORWARD;
    }

    /// @inheritdoc IIntentGuardian
    /// @param context abi.encode(bytes32 method, bytes params). `method` must equal the obligation's
    ///        when it names one; params are the method's own (see _cctp and _across).
    function accept(
        bytes32 intentHash,
        Token calldata token,
        uint256 amount,
        Obligation calldata obligation,
        bytes calldata context
    )
        external
        payable
        returns (bytes32 receipt)
    {
        if (token.tokenType != TokenType.ERC20) {
            revert UnsupportedToken();
        }
        (address input,) = abi.decode(token.data, (address, uint256));
        (bytes32 method, bytes memory params) = abi.decode(context, (bytes32, bytes));
        if (obligation.method != bytes32(0) && obligation.method != method) {
            revert MethodMismatch(obligation.method, method);
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amount);
        if (method == CCTP) {
            _cctp(input, amount, obligation, params);
        } else if (method == ACROSS) {
            _across(input, amount, obligation, params);
        } else {
            revert UnsupportedMethod(method);
        }

        // Neither method takes call value. Whatever was forwarded goes back to the caller, which
        // settles it: an intent address sends its native to the owner, a router back to the keeper.
        if (msg.value > 0) {
            // forge-lint: disable-next-line(arbitrary-send-eth)
            (bool ok,) = msg.sender.call{ value: msg.value }("");
            (ok);
        }

        receipt = keccak256(abi.encode(block.chainid, address(this), ++s_accepted));
        s_status[receipt] = Status.PENDING;
        // The executing keeper isn't visible here (msg.sender is the intent); tx.origin is recorded
        // for reconciliation only.
        // forge-lint: disable-next-line(tx-origin)
        emit Accepted(receipt, intentHash, tx.origin, obligation);
    }

    /// @notice FORWARD has no settlement: delivery is the bridge's, and this guardian verifies no
    ///         proofs. Receipts stay PENDING.
    function settle(bytes32, Status, bytes calldata) external pure {
        revert Unsupported();
    }

    function status(bytes32 receipt) external view returns (Status) {
        return s_status[receipt];
    }

    /// CCTP burns `amount` and mints it to the recipient on the destination, less at most `maxFee`.
    /// params: abi.encode(uint256 maxFee, uint32 minFinalityThreshold)
    function _cctp(address input, uint256 amount, Obligation calldata obligation, bytes memory params) private {
        if (address(tokenMessenger) == address(0) || input != usdc) {
            revert UnsupportedToken();
        }
        Domain memory destination = cctpDestinations[obligation.chainId];
        if (destination.usdc == address(0)) {
            revert UnsupportedDestination(obligation.chainId);
        }
        // CCTP only ever mints native USDC: the committed asset must be exactly that.
        if (obligation.token != destination.usdc) {
            revert WrongDeliveredToken(destination.usdc, obligation.token);
        }
        (uint256 maxFee, uint32 minFinalityThreshold) = abi.decode(params, (uint256, uint32));
        uint256 delivered = maxFee >= amount ? 0 : amount - maxFee;
        if (delivered < obligation.minAmount) {
            revert BelowMinimum(delivered, obligation.minAmount);
        }
        IERC20(input).forceApprove(address(tokenMessenger), amount);
        // Anyone may submit the attestation on the destination (destinationCaller = 0).
        tokenMessenger.depositForBurn(
            amount,
            destination.domain,
            bytes32(uint256(uint160(obligation.recipient))),
            input,
            bytes32(0),
            maxFee,
            minFinalityThreshold
        );
    }

    /// Across: a relayer delivers `outputAmount` of the committed asset on the destination; an
    /// unfilled deposit is refunded to the depositor on this chain after `fillDeadline`.
    /// params: abi.encode(uint256 outputAmount, address exclusiveRelayer, uint32 fillDeadline,
    ///         uint32 exclusivityParameter)
    function _across(address input, uint256 amount, Obligation calldata obligation, bytes memory params) private {
        if (address(spokePool) == address(0)) {
            revert UnsupportedMethod(ACROSS);
        }
        // The depositor receives Across's own refunds. A refund to the intent address would arrive as
        // a fresh deposit and trigger the rule again.
        if (obligation.refund == address(0) || obligation.refund == msg.sender) {
            revert RefundToCaller();
        }
        (uint256 outputAmount, address exclusiveRelayer, uint32 fillDeadline, uint32 exclusivityParameter) =
            abi.decode(params, (uint256, address, uint32, uint32));
        if (outputAmount < obligation.minAmount) {
            revert BelowMinimum(outputAmount, obligation.minAmount);
        }
        if (fillDeadline > obligation.deadline) {
            revert DeadlineTooLate(fillDeadline, obligation.deadline);
        }
        IERC20(input).forceApprove(address(spokePool), amount);
        spokePool.deposit(
            _word(obligation.refund),
            _word(obligation.recipient),
            _word(input),
            _word(obligation.token),
            amount,
            outputAmount,
            obligation.chainId,
            _word(exclusiveRelayer),
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32(block.timestamp),
            fillDeadline,
            exclusivityParameter,
            ""
        );
    }

    function _word(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

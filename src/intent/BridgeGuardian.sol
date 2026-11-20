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

    /// An Across deposit stays open to fills for at least this long.
    uint256 internal constant MIN_FILL_WINDOW = 30 minutes;

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

    /// An Across route: `input` on this chain is delivered as `output` on `chainId`. `decimals` is
    /// the output token's decimals less the input token's.
    struct AcrossRoute {
        address input;
        uint256 chainId;
        address output;
        int8 decimals;
    }

    /// Turns an output amount into input units: amount * mul / div. A zero `div` means no route.
    struct Scale {
        uint128 mul;
        uint128 div;
    }

    /// CCTP on this chain; zero when CCTP isn't supported here.
    ITokenMessengerV2 public immutable tokenMessenger;
    address public immutable usdc;
    /// Across on this chain; zero when Across isn't supported here.
    IAcrossSpokePool public immutable spokePool;

    mapping(uint256 chainId => Domain destination) public cctpDestinations;
    /// Keyed by keccak256(abi.encode(input, chainId, output)).
    mapping(bytes32 route => Scale scale) public acrossRoutes;
    uint256 private s_accepted;

    error UnsupportedToken();
    error UnsupportedMethod(bytes32 method);
    error MethodMismatch(bytes32 committed, bytes32 chosen);
    error UnsupportedDestination(uint256 chainId);
    error UnsupportedRoute();
    error WrongDeliveredToken(address expected, address committed);
    error BelowMinimum(uint256 delivered, uint256 minAmount);
    error AboveInput(uint256 delivered, uint256 amount);
    error DeadlineTooLate(uint32 fillDeadline, uint64 deadline);
    error DeadlineTooEarly(uint32 fillDeadline);
    error RefundToCaller();
    error Unsupported();
    error ZeroAmount();
    error UnexpectedValue();

    /// Zero addresses are valid: a zero messenger or spoke pool means that bridge isn't on this chain.
    // forge-lint: disable-next-item(missing-zero-check)
    constructor(
        ITokenMessengerV2 tokenMessenger_,
        address usdc_,
        CctpDestination[] memory destinations,
        IAcrossSpokePool spokePool_,
        AcrossRoute[] memory routes
    ) {
        tokenMessenger = tokenMessenger_;
        usdc = usdc_;
        spokePool = spokePool_;
        for (uint256 i; i < destinations.length; ++i) {
            CctpDestination memory d = destinations[i];
            cctpDestinations[d.chainId] = Domain({ domain: d.domain, usdc: d.usdc });
        }
        for (uint256 i; i < routes.length; ++i) {
            AcrossRoute memory r = routes[i];
            // casting to 'uint8' is safe because each branch casts a non-negative int8; a gap too
            // wide for uint128 reverts in the checked power
            // forge-lint: disable-next-item(unsafe-typecast)
            acrossRoutes[keccak256(abi.encode(r.input, r.chainId, r.output))] = r.decimals < 0
                ? Scale({ mul: uint128(10) ** uint8(-r.decimals), div: 1 })
                : Scale({ mul: 1, div: uint128(10) ** uint8(r.decimals) });
        }
    }

    function level() external pure returns (Level) {
        return Level.FORWARD;
    }

    /// @inheritdoc IIntentGuardian
    /// @param context abi.encode(uint256 value, bytes32 method, bytes params). `value` is the call
    ///        value the evaluator forwards, always 0 here. `method` must equal the obligation's when
    ///        it names one; params are the method's own (see _cctp and _across).
    function accept(
        bytes32 intentHash,
        address owner,
        address keeper,
        Token calldata token,
        uint256 amount,
        Obligation calldata obligation,
        bytes calldata context
    )
        external
        payable
        returns (bytes32 receipt)
    {
        // Neither method charges a messaging fee in native.
        if (msg.value > 0) {
            revert UnexpectedValue();
        }
        if (token.tokenType != TokenType.ERC20) {
            revert UnsupportedToken();
        }
        (address input,) = abi.decode(token.data, (address, uint256));
        (, bytes32 method, bytes memory params) = abi.decode(context, (uint256, bytes32, bytes));
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
        // A handoff of nothing delivers nothing: it must not count as accepted. The method's own
        // refusals come first.
        if (amount == 0) {
            revert ZeroAmount();
        }

        // The receipt is the running count of this guardian: no slot is written per receipt.
        receipt = bytes32(++s_accepted);
        // The calls above go only to this token and the configured bridges.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Accepted(receipt, intentHash, msg.sender, owner, keeper, amount, obligation);
    }

    /// @notice FORWARD has no settlement: delivery is the bridge's, and this guardian verifies no
    ///         proofs. Receipts stay PENDING.
    function settle(bytes32, Status, bytes calldata) external pure {
        revert Unsupported();
    }

    function status(bytes32 receipt) external view returns (Status) {
        return receipt != 0 && uint256(receipt) <= s_accepted ? Status.PENDING : Status.NONE;
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
    /// unfilled deposit is refunded to the depositor on this chain after `fillDeadline`. Only the
    /// routes fixed at construction are served. `minAmount` counts in input units, as for CCTP.
    /// The deposit names no exclusive relayer: any relayer may fill it from the first block.
    /// params: abi.encode(uint256 outputAmount, uint32 fillDeadline)
    function _across(address input, uint256 amount, Obligation calldata obligation, bytes memory params) private {
        if (address(spokePool) == address(0)) {
            revert UnsupportedMethod(ACROSS);
        }
        // The depositor receives Across's own refunds. A refund to the intent address would arrive as
        // a fresh deposit and trigger the rule again.
        if (obligation.refund == address(0) || obligation.refund == msg.sender) {
            revert RefundToCaller();
        }
        Scale storage scale = acrossRoutes[keccak256(abi.encode(input, obligation.chainId, obligation.token))];
        if (scale.div == 0) {
            revert UnsupportedRoute();
        }
        (uint256 outputAmount, uint32 fillDeadline) = abi.decode(params, (uint256, uint32));
        // The declared output, in input units.
        uint256 delivered = outputAmount * scale.mul / scale.div;
        if (delivered < obligation.minAmount) {
            revert BelowMinimum(delivered, obligation.minAmount);
        }
        // The handed amount must cover the declared output, so the floor binds what was handed too.
        if (delivered > amount) {
            revert AboveInput(delivered, amount);
        }
        if (fillDeadline > obligation.deadline) {
            revert DeadlineTooLate(fillDeadline, obligation.deadline);
        }
        // A deposit that expires at birth can't be filled: the keeper would keep its fee for nothing.
        // A validator's few seconds of timestamp drift are immaterial against the window.
        // forge-lint: disable-next-item(block-timestamp)
        if (fillDeadline < block.timestamp + MIN_FILL_WINDOW) {
            revert DeadlineTooEarly(fillDeadline);
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
            bytes32(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32(block.timestamp),
            fillDeadline,
            0,
            ""
        );
    }

    function _word(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

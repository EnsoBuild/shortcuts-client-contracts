// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IIntentGuardian, Level, Obligation, Status } from "../interfaces/IIntentGuardian.sol";
import { IAcrossSpokePool } from "../interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../interfaces/bridges/ITokenMessengerV2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
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

    /// Permit2, at its canonical address on every chain this guardian runs on.
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// The Permit2 witness of a subsidy: the Across deposit the fee pays for.
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256(
        "Deposit(address caller,bytes32 intentHash,address refund,address recipient,uint256 chainId,address output,uint256 amount,uint256 outputAmount,uint32 fillDeadline)"
    );
    string internal constant DEPOSIT_WITNESS =
        "Deposit witness)Deposit(address caller,bytes32 intentHash,address refund,address recipient,uint256 chainId,address output,uint256 amount,uint256 outputAmount,uint32 fillDeadline)TokenPermissions(address token,uint256 amount)";

    /// The Permit2 witness of a subsidy: the CCTP burn the fee pays for.
    bytes32 public constant BURN_TYPEHASH = keccak256(
        "Burn(address caller,bytes32 intentHash,address recipient,uint256 chainId,uint256 amount,uint256 maxFee,uint32 minFinalityThreshold)"
    );
    string internal constant BURN_WITNESS =
        "Burn witness)Burn(address caller,bytes32 intentHash,address recipient,uint256 chainId,uint256 amount,uint256 maxFee,uint32 minFinalityThreshold)TokenPermissions(address token,uint256 amount)";

    /// A top-up for a handoff: `fee` of the input token, pulled from `payer` through Permit2 with
    /// `payer`'s signature over the bridge call it pays for (a Deposit for Across, a Burn for CCTP).
    /// A zero fee pays nothing, and the other fields are ignored.
    struct Subsidy {
        address payer;
        uint256 fee;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

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

    /// `payer` topped up the bridge call of `receipt` with `fee` of its input token.
    event Subsidized(bytes32 indexed receipt, address indexed payer, uint256 fee);

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
    error RefundNotOwner();
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
        Subsidy memory subsidy;
        if (method == CCTP) {
            subsidy = _cctp(intentHash, input, amount, obligation, params);
        } else if (method == ACROSS) {
            subsidy = _across(intentHash, owner, input, amount, obligation, params);
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
        if (subsidy.fee > 0) {
            // forge-lint: disable-next-line(reentrancy-events)
            emit Subsidized(receipt, subsidy.payer, subsidy.fee);
        }
    }

    /// @notice FORWARD has no settlement: delivery is the bridge's, and this guardian verifies no
    ///         proofs. Receipts stay PENDING.
    function settle(bytes32, Status, bytes calldata) external pure {
        revert Unsupported();
    }

    function status(bytes32 receipt) external view returns (Status) {
        return receipt != 0 && uint256(receipt) <= s_accepted ? Status.PENDING : Status.NONE;
    }

    /// CCTP burns the handed amount and mints it to the recipient on the destination, less at most
    /// `maxFee`. A subsidy adds its fee to the burn, paying Circle's fee on top of what was handed,
    /// so the recipient can receive the whole handed amount. Whatever of the fee Circle doesn't
    /// charge is minted to the recipient too.
    /// params: abi.encode(uint256 maxFee, uint32 minFinalityThreshold, Subsidy subsidy)
    function _cctp(
        bytes32 intentHash,
        address input,
        uint256 amount,
        Obligation calldata obligation,
        bytes memory params
    )
        private
        returns (Subsidy memory subsidy)
    {
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
        uint256 maxFee;
        uint32 minFinalityThreshold;
        (maxFee, minFinalityThreshold, subsidy) = abi.decode(params, (uint256, uint32, Subsidy));
        uint256 burned = amount + subsidy.fee;
        uint256 delivered = maxFee >= burned ? 0 : burned - maxFee;
        if (delivered < obligation.minAmount) {
            revert BelowMinimum(delivered, obligation.minAmount);
        }
        if (subsidy.fee > 0) {
            bytes32 witness = keccak256(
                abi.encode(
                    BURN_TYPEHASH,
                    msg.sender,
                    intentHash,
                    obligation.recipient,
                    obligation.chainId,
                    amount,
                    maxFee,
                    minFinalityThreshold
                )
            );
            _subsidize(input, subsidy, witness, BURN_WITNESS);
        }
        IERC20(input).forceApprove(address(tokenMessenger), burned);
        // Anyone may submit the attestation on the destination (destinationCaller = 0).
        tokenMessenger.depositForBurn(
            burned,
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
    /// A subsidy adds its fee to the deposit's input, paying the relayer on top of what was handed,
    /// so the output can equal the handed amount.
    /// params: abi.encode(uint256 outputAmount, uint32 fillDeadline, Subsidy subsidy)
    function _across(
        bytes32 intentHash,
        address owner,
        address input,
        uint256 amount,
        Obligation calldata obligation,
        bytes memory params
    )
        private
        returns (Subsidy memory subsidy)
    {
        if (address(spokePool) == address(0)) {
            revert UnsupportedMethod(ACROSS);
        }
        // The depositor receives Across's own refunds. A refund to the intent address would arrive as
        // a fresh deposit and trigger the rule again.
        if (obligation.refund == address(0) || obligation.refund == msg.sender) {
            revert RefundToCaller();
        }
        // The depositor can also sign a speed-up that lowers the output and changes the recipient, so
        // only the owner may be the depositor.
        if (obligation.refund != owner) {
            revert RefundNotOwner();
        }
        Scale storage scale = acrossRoutes[keccak256(abi.encode(input, obligation.chainId, obligation.token))];
        if (scale.div == 0) {
            revert UnsupportedRoute();
        }
        uint256 outputAmount;
        uint32 fillDeadline;
        (outputAmount, fillDeadline, subsidy) = abi.decode(params, (uint256, uint32, Subsidy));
        uint256 deposited = amount + subsidy.fee;
        // The declared output, in input units.
        uint256 delivered = outputAmount * scale.mul / scale.div;
        if (delivered < obligation.minAmount) {
            revert BelowMinimum(delivered, obligation.minAmount);
        }
        // The deposit must cover the declared output, so the floor binds what was handed, plus any
        // subsidy, too.
        if (delivered > deposited) {
            revert AboveInput(delivered, deposited);
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
        if (subsidy.fee > 0) {
            bytes32 witness = keccak256(
                abi.encode(
                    DEPOSIT_TYPEHASH,
                    msg.sender,
                    intentHash,
                    obligation.refund,
                    obligation.recipient,
                    obligation.chainId,
                    obligation.token,
                    amount,
                    outputAmount,
                    fillDeadline
                )
            );
            _subsidize(input, subsidy, witness, DEPOSIT_WITNESS);
        }
        IERC20(input).forceApprove(address(spokePool), deposited);
        spokePool.deposit(
            _word(obligation.refund),
            _word(obligation.recipient),
            _word(input),
            _word(obligation.token),
            deposited,
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

    /// Pulls the subsidy's fee from its payer. The witness binds the caller, so a copy of the
    /// signature can't be spent through another caller, and binds the bridge call, so the fee pays
    /// for that call alone. An unfilled Across deposit refunds the fee to the owner with the rest.
    function _subsidize(address input, Subsidy memory subsidy, bytes32 witness, string memory witnessType) private {
        PERMIT2.permitWitnessTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({ token: input, amount: subsidy.fee }),
                nonce: subsidy.nonce,
                deadline: subsidy.deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({ to: address(this), requestedAmount: subsidy.fee }),
            subsidy.payer,
            witness,
            witnessType,
            subsidy.signature
        );
    }

    function _word(address account) private pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

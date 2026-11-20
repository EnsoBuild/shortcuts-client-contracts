// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../../../../../src/intent/BridgeGuardian.sol";
import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import {
    Asset,
    Codes,
    Constraints,
    Handoff,
    Intent,
    Predicate,
    Refund,
    Rule,
    Source,
    Term
} from "../../../../../src/interfaces/IIntent.sol";
import { Level } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IAcrossSpokePool } from "../../../../../src/interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../../../../../src/interfaces/bridges/ITokenMessengerV2.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { MockBlockingERC20 } from "../../../../mocks/MockBlockingERC20.sol";
import { MockAcrossSpokePool, MockTokenMessengerV2 } from "../../../../mocks/MockBridges.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import {
    EphemeralIntentExecutor_Unit_Concrete_Test
} from "../../wallet/ephemeralIntentExecutor/EphemeralIntentExecutor.t.sol";

/// The first UDA ruleset end to end: one address, USDC bridged through CCTP and USDT through Across
/// to Arbitrum, each within 0.1% of what arrived less a fixed 1-token fee.
contract BridgeGuardian_Uda_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant ARBITRUM = 42_161;
    uint256 internal constant DEPOSIT = 100e6;
    uint256 internal constant FEE = 1e6;

    MockERC20 internal s_usdc;
    MockBlockingERC20 internal s_blockableUsdc; // s_usdc, with its blocklist
    MockERC20 internal s_usdt;
    address internal s_usdcArbitrum = makeAddr("USDC on Arbitrum");
    address internal s_usdtArbitrum = makeAddr("USDT on Arbitrum");
    MockTokenMessengerV2 internal s_messenger;
    MockAcrossSpokePool internal s_spokePool;
    BridgeGuardian internal s_guardian;

    function setUp() public override {
        super.setUp();
        s_blockableUsdc = new MockBlockingERC20("USD Coin", "USDC");
        s_usdc = s_blockableUsdc;
        s_usdt = new MockERC20("Tether", "USDT");
        s_messenger = new MockTokenMessengerV2();
        s_spokePool = new MockAcrossSpokePool();
        BridgeGuardian.CctpDestination[] memory destinations = new BridgeGuardian.CctpDestination[](1);
        destinations[0] = BridgeGuardian.CctpDestination({ chainId: ARBITRUM, domain: 3, usdc: s_usdcArbitrum });
        BridgeGuardian.AcrossRoute[] memory routes = new BridgeGuardian.AcrossRoute[](1);
        routes[0] = BridgeGuardian.AcrossRoute({
            input: address(s_usdt), chainId: ARBITRUM, output: s_usdtArbitrum, decimals: 0
        });
        s_guardian = new BridgeGuardian(
            ITokenMessengerV2(address(s_messenger)),
            address(s_usdc),
            destinations,
            IAcrossSpokePool(address(s_spokePool)),
            routes
        );
    }

    function _uda() internal view returns (Intent memory) {
        Constraints memory c = _constraints(address(0));
        c.assets = new Asset[](4);
        c.assets[0] = _erc20(address(s_usdc));
        c.assets[1] = _erc20(address(s_usdt));
        c.assets[2] = Asset({ kind: Codes.ERC20, chainId: ARBITRUM, token: s_usdcArbitrum, id: 0 });
        c.assets[3] = Asset({ kind: Codes.ERC20, chainId: ARBITRUM, token: s_usdtArbitrum, id: 0 });
        c.sources = new Source[](1);
        c.sources[0] =
            Source({ kind: Codes.GUARDIAN, target: address(s_guardian), config: abi.encode(uint8(Level.FORWARD)) });

        c.refunds = new Refund[](2);
        c.refunds[0] = Refund({ asset: 0, fee: 10e6 });
        c.refunds[1] = Refund({ asset: 1, fee: 10e6 });

        c.terms = new Term[](12);
        c.terms[0] = _term(Codes.OP_CONSUMED, 0, 0, 0); // USDC consumed
        c.terms[1] = _term(Codes.OP_MUL_BPS, 0, 0, 9990);
        c.terms[2] = _term(Codes.OP_CONST, 0, 0, FEE);
        c.terms[3] = _term(Codes.OP_SUB, 1, 2, 0); // USDC minimum
        c.terms[4] = _term(Codes.OP_CONSUMED, 1, 0, 0); // USDT consumed
        c.terms[5] = _term(Codes.OP_MUL_BPS, 4, 0, 9990);
        c.terms[6] = _term(Codes.OP_SUB, 5, 2, 0); // USDT minimum
        c.terms[7] = _term(Codes.OP_NOW, 0, 0, 0);
        c.terms[8] = _term(Codes.OP_CONST, 0, 0, 1 hours);
        c.terms[9] = _term(Codes.OP_ADD, 7, 8, 0); // CCTP deadline
        c.terms[10] = _term(Codes.OP_CONST, 0, 0, 6 hours);
        c.terms[11] = _term(Codes.OP_ADD, 7, 10, 0); // Across deadline

        c.handoffs = new Handoff[](2);
        c.handoffs[0] = Handoff({
            source: 0,
            chainId: ARBITRUM,
            method: keccak256("cctp"),
            recipient: s_user,
            refund: s_user,
            input: 0,
            asset: 2,
            minAmount: 3,
            deadline: 9
        });
        c.handoffs[1] = Handoff({
            source: 0,
            chainId: ARBITRUM,
            method: keccak256("across"),
            recipient: s_user,
            refund: s_user,
            input: 1,
            asset: 3,
            minAmount: 6,
            deadline: 11
        });
        c.predicates = new Predicate[](2);
        c.predicates[0] = _pred(Codes.CMP_ACCEPTED, 0, 0);
        c.predicates[1] = _pred(Codes.CMP_ACCEPTED, 1, 0);
        c.rules = new Rule[](2);
        c.rules[0] = _rule(_input(0, 10e6), _one(0), 0, 2, Codes.DRAIN);
        c.rules[1] = _rule(_input(1, 10e6), _one(1), 1, 2, Codes.DRAIN);
        // Bridge rules run no route: the funds go straight from the address to the guardian.
        c.rules[0].routing = Codes.ROUTE_NONE;
        c.rules[1].routing = Codes.ROUTE_NONE;
        Intent memory intent = _intent(c, s_user, s_keeper);
        intent.deadline = uint64(block.timestamp + 365 days);
        return intent;
    }

    /// Context per handoff: CCTP with a 0.05 USDC fee cap, fast; Across at 98.95 out, filled within 2h.
    function _execution(Intent memory intent, uint256 outputAmount) internal view returns (Execution memory e) {
        e = _execution(intent);
        e.contexts = new bytes[](2);
        e.contexts[0] = abi.encode(uint256(0), keccak256("cctp"), abi.encode(uint256(0.05e6), uint32(1000)));
        e.contexts[1] =
            abi.encode(uint256(0), keccak256("across"), abi.encode(outputAmount, uint32(block.timestamp + 2 hours)));
    }

    function test_Usdc_BridgesThroughCctp() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, DEPOSIT);

        _run(s_keeper, root, _execution(intent, 0));

        (uint256 amount, uint32 domain, bytes32 mintRecipient,,, uint256 maxFee,) = s_messenger.last();
        assertEq(amount, DEPOSIT - FEE, "the deposit less the fee");
        assertEq(domain, 3, "Arbitrum");
        assertEq(mintRecipient, bytes32(uint256(uint160(address(s_user)))), "to the user");
        assertEq(maxFee, 0.05e6, "fee cap within the 0.1% floor");
        assertEq(s_usdc.balanceOf(s_keeper), FEE, "rule fee");
        assertEq(s_usdc.balanceOf(at), 0, "drained");
        assertEq(s_spokePool.deposits(), 0, "USDT rule inactive");
    }

    function test_Usdt_BridgesThroughAcross() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdt.mint(at, DEPOSIT);

        _run(s_keeper, root, _execution(intent, 98.95e6));

        MockAcrossSpokePool.Deposit memory d = s_spokePool.last();
        assertEq(d.inputAmount, DEPOSIT - FEE, "the deposit less the fee");
        assertEq(d.outputAmount, 98.95e6, "at least 99.9% of 100, less the fee");
        assertEq(d.depositor, bytes32(uint256(uint160(address(s_user)))), "Across refunds go to the user");
        assertEq(d.outputToken, bytes32(uint256(uint160(s_usdtArbitrum))), "committed delivered asset");
        assertEq(s_messenger.burns(), 0, "USDC rule inactive");
    }

    function test_Usdt_BelowTheFloor_Reverts() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        s_usdt.mint(s_factory.getAddress(root), DEPOSIT);
        Execution memory e = _execution(intent, 98.89e6); // floor is 98.9

        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.BelowMinimum.selector, 98.89e6, 98.9e6));
        _run(s_keeper, root, e);
    }

    function test_BothArrive_BothBridgeInOneExecution() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, DEPOSIT);
        s_usdt.mint(at, DEPOSIT);

        _run(s_keeper, root, _execution(intent, 98.95e6));
        assertEq(s_messenger.burns(), 1, "USDC through CCTP");
        assertEq(s_spokePool.deposits(), 1, "USDT through Across");
        assertEq(s_usdc.balanceOf(s_keeper) + s_usdt.balanceOf(s_keeper), 2 * FEE, "a fee per rule");
    }

    function test_OtherTokens_ReturnToTheUser() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, DEPOSIT);
        s_tokenIn.mint(at, 5 ether); // a token the template doesn't accept

        Execution memory e = _execution(intent, 0);
        e.sweep = _sweepOf(address(s_tokenIn));
        _run(s_keeper, root, e);
        assertEq(s_tokenIn.balanceOf(s_user), 5 ether, "swept back to the owner");
    }

    /// A keeper can't add a route to a rule that runs none: its bytes are ignored, so nothing can be
    /// skimmed between the deposit and the handoff.
    function test_KeeperRouteBytes_AreIgnored() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, DEPOSIT);

        Execution memory e = _execution(intent, 0);
        e.router = address(s_router);
        e.routes = new bytes[](1);
        e.routes[0] = hex"c0ffee";
        _run(s_keeper, root, e);

        assertEq(s_router.calls(), 0, "no route ran");
        (uint256 amount,,,,,,) = s_messenger.last();
        assertEq(amount, DEPOSIT - FEE, "everything but the fee reached the bridge");
    }

    function test_BelowTheMinimum_Waits() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, 5e6); // below the 10 USDC minimum: absent

        Execution memory e = _execution(intent, 0);
        vm.expectRevert(bytes4(keccak256("NotExecutable()")));
        _run(s_keeper, root, e);

        vm.roll(block.number + 1);
        s_usdc.mint(at, 5e6); // the next deposit tops it up
        // The floor scales with the deposit (10 × 99.9% − 1 = 8.99), so the keeper sizes its fee cap
        // to fit: 0.01 here, where 0.05 would be refused.
        e.contexts[0] = abi.encode(uint256(0), keccak256("cctp"), abi.encode(uint256(0.01e6), uint32(1000)));
        _run(s_keeper, root, e);
        (uint256 amount,,,,,,) = s_messenger.last();
        assertEq(amount, 10e6 - FEE, "both deposits together");
    }

    // Shared outcomes under ALL matching

    /// A handoff is accepted once per execution: a second rule naming it would pass on the first
    /// rule's acceptance with nothing of its own handed over.
    function test_TwoRulesNamingOneHandoff_IsMalformed() external view {
        Intent memory intent = _uda();
        intent.constraints.rules[1].then = _one(0);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.MALFORMED, "status");
    }

    /// Post-state is measured once, after every rule: a second rule comparing the same balance
    /// change would pass on what the first rule delivered.
    function test_TwoRulesComparingOneBalanceChange_IsMalformed() external view {
        Intent memory intent = _uda();
        Constraints memory c = intent.constraints;
        Term[] memory terms = new Term[](14);
        for (uint256 i; i < 12; ++i) {
            terms[i] = c.terms[i];
        }
        terms[12] = _term(Codes.OP_DELTA, 0, Codes.OWNER, 0);
        terms[13] = _term(Codes.OP_CONST, 0, 0, 0);
        c.terms = terms;
        Predicate[] memory predicates = new Predicate[](3);
        predicates[0] = c.predicates[0];
        predicates[1] = c.predicates[1];
        predicates[2] = _pred(Codes.CMP_GTE, 12, 13);
        c.predicates = predicates;
        c.rules[0].then = _two(0, 2);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.OK, "one rule");
        c.rules[1].then = _two(1, 2);
        assertEq(IntentEvaluator.check(intent), IntentEvaluator.MALFORMED, "two rules");
    }

    // Handoff minimums

    /// A guardian bound to deliver nothing bounds nothing: the handoff doesn't run.
    function test_HandoffMinimumOfZero_Reverts() external {
        Intent memory intent = _uda();
        Constraints memory c = intent.constraints;
        Term[] memory terms = new Term[](13);
        for (uint256 i; i < 12; ++i) {
            terms[i] = c.terms[i];
        }
        terms[12] = _term(Codes.OP_CONST, 0, 0, 0);
        c.terms = terms;
        c.handoffs[0].minAmount = 12;
        bytes32 root = _root(intent);
        s_usdc.mint(s_factory.getAddress(root), DEPOSIT);

        Execution memory e = _execution(intent, 0);
        vm.expectRevert(IntentEvaluator.NotExecutable.selector);
        _run(s_keeper, root, e);
    }

    // Refunds

    /// The refund fee follows the refund it rewards: while the owner can't receive, a caller earns
    /// nothing, so repeating the refund can't drain the address.
    function test_Refund_OwnerBlocked_PaysNoFee() external {
        Intent memory intent = _uda();
        bytes32 root = _root(intent);
        address at = s_factory.getAddress(root);
        s_usdc.mint(at, DEPOSIT);
        s_blockableUsdc.setBlocked(s_user, true);
        vm.warp(uint256(intent.deadline) + 1);

        _run(s_stranger, root, _execution(intent));
        assertEq(s_usdc.balanceOf(s_stranger), 0, "no fee");
        assertEq(s_usdc.balanceOf(at), DEPOSIT, "the deposit stays");

        s_blockableUsdc.setBlocked(s_user, false);
        _run(s_stranger, root, _execution(intent));
        assertEq(s_usdc.balanceOf(s_stranger), 10e6, "one refund fee");
        assertEq(s_usdc.balanceOf(s_user), DEPOSIT - 10e6, "the rest to the owner");
    }
}

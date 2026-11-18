// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import {
    Asset,
    Codes,
    Constraints,
    Handoff,
    Intent,
    Predicate,
    Rule,
    Source,
    Term,
    View
} from "../../../../../src/interfaces/IIntent.sol";
import { Level, Obligation } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { MockGuardian } from "../../../../mocks/MockGuardian.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract EphemeralIntentExecutor_Handoff_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;
    uint256 internal constant FEE = 1 ether;
    uint256 internal constant DESTINATION = 42_161;

    MockGuardian internal s_guardian;

    function setUp() public override {
        super.setUp();
        s_guardian = new MockGuardian(Level.FORWARD);
        vm.label(address(s_guardian), "Guardian");
    }

    function _bridgeIntent() internal view returns (Intent memory) {
        Constraints memory c = _bridge(
            address(s_guardian), uint8(Level.FORWARD), address(s_tokenIn), DESTINATION, s_user, s_user, 10 ether, FEE
        );
        return _intent(c, s_user, s_keeper);
    }

    function test_HandsTheWholeBalanceLessTheFee() external {
        Intent memory intent = _bridgeIntent();
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);

        _run(s_keeper, root, _execution(intent));

        assertEq(s_tokenIn.balanceOf(s_keeper), FEE, "fee first");
        assertEq(s_guardian.lastAmount(), DEPOSIT - FEE, "the rest to the guardian");
        assertEq(s_tokenIn.balanceOf(address(s_guardian)), DEPOSIT - FEE, "pulled");
        assertEq(s_tokenIn.balanceOf(at), 0, "drained");
        assertEq(s_tokenIn.allowance(at, address(s_guardian)), 0, "approval revoked");

        Obligation memory o = s_guardian.lastObligation();
        assertEq(o.chainId, DESTINATION, "destination");
        assertEq(o.method, keccak256("cctp"), "method");
        assertEq(o.recipient, s_user, "recipient");
        assertEq(o.refund, s_user, "refund");
        assertEq(o.token, address(s_tokenIn), "delivered asset");
        assertEq(o.minAmount, DEPOSIT - FEE, "minimum = consumed - fee");
        assertEq(o.deadline, block.timestamp + 6 hours, "deadline = now + window");
        assertTrue(s_guardian.lastIntentHash() != bytes32(0), "intent hash passed");
    }

    function test_PassesTheKeepersContext() external {
        Intent memory intent = _bridgeIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        Execution memory e = _execution(intent);
        e.contexts = new bytes[](1);
        e.contexts[0] = abi.encode(uint256(7), uint32(1000));
        _run(s_keeper, root, e);
        assertEq(s_guardian.lastContext(), abi.encode(uint256(7), uint32(1000)), "context");
    }

    function test_WrongLevel_Reverts() external {
        Intent memory intent = _bridgeIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        s_guardian.setLevel(Level.BONDED);

        vm.expectRevert(abi.encodeWithSelector(IntentEvaluator.WrongLevel.selector, uint16(0)));
        _run(s_keeper, root, _execution(intent));
    }

    function test_ForwardsTheKeepersNativeForMessagingFees() external {
        Intent memory intent = _bridgeIntent();
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        vm.deal(at, 0.01 ether); // the keeper funds the address in the same batch

        _run(s_keeper, root, _execution(intent));
        assertEq(s_guardian.lastValue(), 0.01 ether, "native forwarded as call value");
    }

    function test_Exact_HandsOnlyTheMinimum() external {
        Intent memory intent = _bridgeIntent();
        intent.constraints.rules[0].consume = Codes.EXACT;
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);

        _run(s_keeper, root, _execution(intent));
        assertEq(s_guardian.lastAmount(), 10 ether - FEE, "the minimum, less the fee");
        assertEq(s_tokenIn.balanceOf(at), DEPOSIT - 10 ether, "the rest stays");
    }

    /// After a keeper route, the handoff's minimum reads a view the route moves: it is fixed before
    /// the route runs. Assets: 0 tokenIn, 1 tokenOut here, 2 tokenOut there.
    ///   terms: 0 CONST 200, 1 PRE_VIEW(stranger's tokenOut), 2 SUB(0, 1), 3 NOW, 4 CONST window, 5 ADD(3, 4)
    function test_Minimum_IsFixedBeforeTheRoute() external {
        Constraints memory c = _constraints(address(s_router));
        c.assets = new Asset[](3);
        c.assets[0] = _erc20(address(s_tokenIn));
        c.assets[1] = _erc20(address(s_tokenOut));
        c.assets[2] = Asset({ kind: Codes.ERC20, chainId: DESTINATION, token: address(s_tokenOut), id: 0 });
        c.sources = new Source[](1);
        c.sources[0] =
            Source({ kind: Codes.GUARDIAN, target: address(s_guardian), config: abi.encode(uint8(Level.FORWARD)) });
        c.views = new View[](1);
        c.views[0] = View({
            target: address(s_tokenOut), selector: IERC20.balanceOf.selector, args: abi.encode(s_stranger), word: 0
        });
        c.terms = new Term[](6);
        c.terms[0] = _term(Codes.OP_CONST, 0, 0, 200 ether);
        c.terms[1] = _term(Codes.OP_PRE_VIEW, 0, 0, 0);
        c.terms[2] = _term(Codes.OP_SUB, 0, 1, 0);
        c.terms[3] = _term(Codes.OP_NOW, 0, 0, 0);
        c.terms[4] = _term(Codes.OP_CONST, 0, 0, 6 hours);
        c.terms[5] = _term(Codes.OP_ADD, 3, 4, 0);
        c.handoffs = new Handoff[](1);
        c.handoffs[0] = Handoff({
            source: 0,
            chainId: DESTINATION,
            method: keccak256("cctp"),
            recipient: s_user,
            refund: s_user,
            input: 1,
            asset: 2,
            minAmount: 2,
            deadline: 5
        });
        c.predicates = new Predicate[](1);
        c.predicates[0] = _pred(Codes.CMP_ACCEPTED, 0, 0);
        c.rules = new Rule[](1);
        c.rules[0] = _rule(_input(0, DEPOSIT), _one(0), NONE, NONE, Codes.DRAIN);
        Intent memory intent = _intent(c, s_user, s_keeper);
        bytes32 root = _root(intent);
        address holder = _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, holder);
        s_router.addOut(address(s_tokenOut), 150 ether, s_stranger);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_guardian.lastAmount(), 200 ether, "the route's output handed over");
        assertEq(s_guardian.lastObligation().minAmount, 200 ether, "200 less the stranger's pre-state holding");
    }
}

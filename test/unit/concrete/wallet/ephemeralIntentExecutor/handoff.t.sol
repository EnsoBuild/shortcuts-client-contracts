// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Codes, Constraints, Intent } from "../../../../../src/interfaces/IIntent.sol";
import { Level, Obligation } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { MockGuardian } from "../../../../mocks/MockGuardian.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

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
}

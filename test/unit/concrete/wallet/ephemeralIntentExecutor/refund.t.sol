// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Codes, Constraints, Intent, Rule } from "../../../../../src/interfaces/IIntent.sol";
import { EphemeralIntentExecutor } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Refund_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;
    uint256 internal constant REFUND_FEE = 0.5 ether;

    function _swapIntent() internal view returns (Intent memory) {
        Constraints memory c = _swap(
            address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, REFUND_FEE, Codes.DRAIN
        );
        return _intent(c, s_user, s_keeper);
    }

    /// The same intent for another chain: its leaf proves, but not here. Built fresh: assigning a
    /// memory struct aliases it.
    function _elsewhere() internal view returns (Intent memory other) {
        other = _swapIntent();
        other.chainId = block.chainid + 1;
    }

    /// A default leaf: chain 0, no rules, no inputs.
    function _defaultLeaf(address owner) internal view returns (Intent memory) {
        Intent memory leaf = _intent(_constraints(address(0)), owner, address(0));
        leaf.chainId = 0;
        return leaf;
    }

    function test_AfterDeadline_AnyoneRefundsForTheFee() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        vm.warp(intent.deadline + 1);

        _run(s_stranger, root, _execution(intent));

        assertEq(s_tokenIn.balanceOf(s_stranger), REFUND_FEE, "refund fee");
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT - REFUND_FEE, "rest to the owner");
        assertEq(s_tokenIn.balanceOf(at), 0, "empty");
    }

    function test_RefundOnlyChain_RefundsImmediately() external {
        Constraints memory c = _swap(
            address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, REFUND_FEE, Codes.DRAIN
        );
        c.rules = new Rule[](0); // listed for mistaken deposits: nothing to execute
        Intent memory intent = _intent(c, s_user, s_keeper);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        _run(s_stranger, root, _execution(intent));
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT - REFUND_FEE, "returned at once, less the fee");
    }

    function test_DefaultLeaf_OwnerRecoversOnAnUncoveredChain() external {
        // The tree covers another chain only, plus the default leaf.
        Intent memory other = _elsewhere();
        Intent memory fallback_ = _defaultLeaf(s_user);
        (bytes32 root,, bytes32[] memory proof) = _pair(other, fallback_);
        address at = _fund(root, DEPOSIT);

        Execution memory e = _execution(fallback_);
        e.proof = proof;
        e.sweep = _sweepOf(address(s_tokenIn));
        _run(s_user, root, e);

        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "the owner's sweep, no fee");
        assertEq(s_tokenIn.balanceOf(at), 0, "empty");
    }

    function test_DefaultLeaf_RevertsForAnyoneButTheOwner() external {
        Intent memory other = _elsewhere();
        Intent memory fallback_ = _defaultLeaf(s_user);
        (bytes32 root,, bytes32[] memory proof) = _pair(other, fallback_);
        _fund(root, DEPOSIT);

        Execution memory e = _execution(fallback_);
        e.proof = proof;
        vm.expectRevert(EphemeralIntentExecutor.InvalidProof.selector);
        _run(s_stranger, root, e);
    }

    function test_AnotherChainsLeaf_Reverts() external {
        Intent memory other = _elsewhere();
        Intent memory fallback_ = _defaultLeaf(s_user);
        (bytes32 root, bytes32[] memory proof,) = _pair(other, fallback_);
        _fund(root, DEPOSIT);

        Execution memory e = _execution(other);
        e.proof = proof;
        vm.expectRevert(EphemeralIntentExecutor.InvalidProof.selector);
        _run(s_keeper, root, e);
    }

    function test_BadProof_Reverts() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        Execution memory e = _execution(intent);
        e.proof = new bytes32[](1);
        e.proof[0] = keccak256("not a sibling");
        vm.expectRevert(EphemeralIntentExecutor.InvalidProof.selector);
        _run(s_keeper, root, e);
    }

    function test_TwoChainTree_ExecutesThisChainsLeaf() external {
        Intent memory here = _swapIntent();
        Intent memory other = _elsewhere();
        (bytes32 root, bytes32[] memory proof,) = _pair(here, other);
        _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);

        Execution memory e = _withRoute(_execution(here), hex"c0ffee");
        e.proof = proof;
        _run(s_keeper, root, e);
        assertEq(s_tokenOut.balanceOf(s_user), 200 ether, "delivered");
    }
}

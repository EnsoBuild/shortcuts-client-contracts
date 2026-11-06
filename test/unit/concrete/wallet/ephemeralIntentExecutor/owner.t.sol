// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Constraints, Intent } from "../../../../../src/interfaces/IIntent.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

/// The owner's arms: refund or re-route at any block, whatever the keeper field says.
contract EphemeralIntentExecutor_Owner_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;

    function _swapIntent() internal view returns (Intent memory) {
        Constraints memory c = _swap(
            address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0.5 ether, Codes.DRAIN
        );
        return _intent(c, s_user, s_keeper);
    }

    function test_OwnerRefund_AnyTimeWithoutFee() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        _run(s_user, root, _execution(intent));
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "everything, no fee");
    }

    function test_OwnerRefund_BeforeStart() external {
        Intent memory intent = _swapIntent();
        intent.start = uint64(block.timestamp + 1 days);
        intent.deadline = uint64(block.timestamp + 2 days);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        _run(s_user, root, _execution(intent));
        assertEq(s_tokenIn.balanceOf(s_user), DEPOSIT, "the owner's exit ignores the window");
    }

    function test_OwnerRoute_RunsTheOwnersBytes() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        _run(s_user, root, _withRoute(_execution(intent), hex"0123"));
        assertEq(s_router.lastData(), hex"0123", "owner bytes");
        assertEq(s_tokenIn.balanceOf(address(s_router)), DEPOSIT, "live balance, unvalidated");
        assertEq(s_tokenIn.allowance(s_factory.getAddress(root), address(s_router)), 0, "approval revoked");
    }

    function test_ZeroOwner_ElevatesNobody() external {
        Intent memory intent = _swapIntent();
        intent.owner = address(0);
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        vm.warp(intent.deadline + 1);

        // The refund falls to the caller as beneficiary instead of burning at address zero.
        _run(s_stranger, root, _execution(intent));
        assertEq(s_tokenIn.balanceOf(s_stranger), DEPOSIT, "caller substituted, and no fee to itself");
        assertEq(s_tokenIn.balanceOf(at), 0, "empty");
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Codes, Constraints, Intent } from "../../../../../src/interfaces/IIntent.sol";
import { IntentEvaluator } from "../../../../../src/libraries/IntentEvaluator.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Route_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;
    uint256 internal constant FEE = 1 ether;

    /// Swap 100 TIN with a 2 TOUT/TIN floor on what was consumed (fee included): at least 200 TOUT.
    function _swapIntent(uint8 consume) internal view returns (Intent memory) {
        Constraints memory c =
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, FEE, 0, consume);
        return _intent(c, s_user, s_keeper);
    }

    function test_WhenFloorMet_DeliversAndPaysFeeFirst() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);

        address executor = _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));

        assertEq(executor, at, "deployed at the derived address");
        assertEq(s_tokenIn.balanceOf(s_keeper), FEE, "fee to the keeper");
        assertEq(s_tokenIn.balanceOf(address(s_router)), DEPOSIT - FEE, "route got the rest");
        assertEq(s_tokenIn.balanceOf(at), 0, "drained");
        assertEq(s_tokenOut.balanceOf(s_user), 200 ether, "delivered to the owner");
        assertEq(s_router.lastData(), hex"c0ffee", "keeper bytes");
        assertEq(s_tokenIn.allowance(at, address(s_router)), 0, "approval revoked");
    }

    function test_WhenFloorMissed_Reverts() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 199 ether, s_user);

        vm.expectRevert(abi.encodeWithSelector(IntentEvaluator.PredicateFailed.selector, uint16(0)));
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenIn.balanceOf(at), DEPOSIT, "funds stay for a later attempt or refund");
    }

    function test_Exact_ConsumesTheMinimumAndLeavesTheRest() external {
        Intent memory intent = _swapIntent(Codes.EXACT);
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT + 50 ether);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));

        assertEq(s_tokenIn.balanceOf(address(s_router)), DEPOSIT - FEE, "exactly the minimum, less the fee");
        assertEq(s_tokenIn.balanceOf(at), 50 ether, "the rest stays at the address");
    }

    function test_AddressIsReusable() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));

        // A second deposit in a later transaction runs again at the same address.
        vm.roll(block.number + 1);
        _fund(root, DEPOSIT);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_tokenOut.balanceOf(s_user), 400 ether, "both deposits delivered");
    }

    function test_CommittedRoute_IgnoresKeeperBytesAndNeedsNoFloor() external {
        Constraints memory c =
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0, Codes.DRAIN);
        c.rules[0].then = new uint16[](0); // no outcome predicate: the committed bytes are the constraint
        c.rules[0].routing = Codes.ROUTE_COMMITTED;
        c.rules[0].route = hex"beef";
        Intent memory intent = _intent(c, s_user, s_keeper);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);

        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(s_router.lastData(), hex"beef", "committed bytes ran");
    }

    function test_NotKeeper_RevertsUntilExclusiveHandover() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        intent.exclusive = uint64(block.timestamp + 1 hours);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);
        Execution memory e = _withRoute(_execution(intent), hex"c0ffee");

        vm.expectRevert(bytes4(keccak256("NotKeeper()")));
        _run(s_stranger, root, e);

        vm.warp(block.timestamp + 1 hours);
        _run(s_stranger, root, e);
        assertEq(s_tokenIn.balanceOf(s_stranger), FEE, "after the handover, anyone executes for the fee");
    }

    function test_KeeperForever_WhenExclusiveIsZero() external {
        Intent memory intent = _swapIntent(Codes.DRAIN);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        vm.warp(block.timestamp + 12 hours);

        vm.expectRevert(bytes4(keccak256("NotKeeper()")));
        _run(s_stranger, root, _withRoute(_execution(intent), hex"c0ffee"));
    }
}

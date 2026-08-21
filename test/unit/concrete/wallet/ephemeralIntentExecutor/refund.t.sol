// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockRevertingERC20 } from "../../../../mocks/MockRevertingERC20.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Refund_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    function test_WhenTheDeadlineHasPassed() external {
        Intent memory intent = _intent();
        intent.keeperFee.amount = 5 ether;
        address predicted = _fund(intent, 100 ether);

        MockERC20 extra = new MockERC20("Extra", "EXT");
        extra.mint(predicted, 42 ether);
        MockRevertingERC20 reverting = new MockRevertingERC20();

        vm.warp(intent.deadline + 1);

        address[] memory sweep = new address[](2);
        sweep[0] = address(reverting);
        sweep[1] = address(extra);
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", sweep);

        // it should pay the keeper fee best-effort
        assertEq(s_tokenIn.balanceOf(s_keeper), 5 ether);

        // it should sweep trigger tokens to the refund recipient
        assertEq(s_tokenIn.balanceOf(s_user), 95 ether);

        // it should sweep keeper-listed tokens to the refund recipient
        // it should not revert on a reverting token
        assertEq(extra.balanceOf(s_user), 42 ether);
    }

    function test_WhenExecutedOnTheWrongChain() external {
        Intent memory intent = _intent();
        intent.chainId = 999; // committed for another chain
        intent.starttime = uint64(block.timestamp + 1 hours); // gates must not apply
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 1 ether);

        _execute(intent, "");

        // it should sweep immediately without waiting for the gates
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);

        // it should sweep native via selfdestruct
        assertEq(s_user.balance, 1 ether);
    }
}

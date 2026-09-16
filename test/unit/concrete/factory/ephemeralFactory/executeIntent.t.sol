// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Constrained, Intent, Mode } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_ExecuteIntent_Unit_Concrete_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_WhenTheIntentExecutes() external {
        Intent memory intent = _intent();
        address predicted = _fund(intent, 100 ether);

        // it should emit IntentPublished with the canonical blob
        vm.expectEmit(address(s_factory));
        emit EphemeralFactory.IntentPublished(predicted, abi.encode(intent));

        vm.prank(s_keeper);
        address executor = s_factory.executeIntent(intent, "", new Token[](0));

        // it should deploy at the predicted address
        assertEq(executor, predicted);

        // it should leave no code at the address
        assertEq(predicted.code.length, 0);
    }

    function test_WhenTheRouterReadsTheContext() external {
        // ROUTE mode: the keeper-supplied route bytes are ignored by the executor but
        // still ride the transient context, which is what the probe asserts on.
        Intent memory intent = _intent();
        _fund(intent, 100 ether);
        s_router.setProbe(address(s_factory));

        Token[] memory sweep = new Token[](1);
        sweep[0] = Token({ tokenType: TokenType.ERC20, data: abi.encode(address(s_tokenIn), uint256(0)) });
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, hex"beefcafe", sweep);

        // it should expose route, sweep, keeper and router
        assertEq(s_router.probedRoute(), hex"beefcafe");
        assertEq(s_router.probedSweepLength(), 1);
        (TokenType sweptType, bytes memory sweptData) = s_router.probedSweep(0);
        assertEq(uint8(sweptType), uint8(TokenType.ERC20));
        assertEq(sweptData, abi.encode(address(s_tokenIn), uint256(0)));
        assertEq(s_router.probedKeeper(), s_keeper);
        assertEq(s_router.probedRouter(), address(s_router));
    }

    /// forge-config: default.isolate = true
    function test_WhenExecutedTwiceWithTheSameIntent() external {
        Intent memory intent = _intent();
        address predicted = _fund(intent, 100 ether);
        vm.warp(intent.deadline + 1); // refund branch: no router interaction needed

        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
        assertEq(predicted.code.length, 0);

        // it should reuse the address
        s_tokenIn.mint(predicted, 50 ether);
        vm.prank(s_keeper);
        address executor = s_factory.executeIntent(intent, "", new Token[](0));
        assertEq(executor, predicted);
        assertEq(s_tokenIn.balanceOf(s_user), 150 ether);
    }
}

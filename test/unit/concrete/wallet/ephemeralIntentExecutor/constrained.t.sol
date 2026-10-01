// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent } from "../../../../../src/interfaces/IIntent.sol";
import { EphemeralIntentExecutor } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockERC721 } from "../../../../mocks/MockERC721.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

/// The keeper-routed (constrained) arm: `intent.route` is empty, the factory's keeper
/// supplies the bytes, and the tokensOut minimums at the recipient are the constraint.
contract EphemeralIntentExecutor_Constrained_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    function test_WhenTheDeltaClearsTheMinimum() external {
        Intent memory intent = _constrainedIntent(50 ether);
        _fund(intent, 100 ether);
        s_tokenOut.mint(s_recipient, 100 ether); // pre-existing balance must not count
        s_router.setOut(address(s_tokenOut), 60 ether, s_recipient);

        _execute(intent, hex"beefcafe");

        // it should call the router with the keeper route
        assertEq(s_router.lastData(), hex"beefcafe");

        // it should measure the delta at the recipient
        assertEq(s_tokenOut.balanceOf(s_recipient), 160 ether);
    }

    function test_WhenTokenOutIsNative() external {
        Intent memory intent = _constrainedIntent(1 ether);
        intent.tokensOut[0] = _native(1 ether);
        _fund(intent, 100 ether);
        vm.deal(address(s_router), 2 ether);
        s_router.setOutNative(2 ether, s_recipient);

        _execute(intent, hex"beefcafe");

        // it should measure the native delta at the recipient
        assertEq(s_recipient.balance, 2 ether);
    }

    function test_WhenAnyTokenOutMissesItsMinimum() external {
        Intent memory intent = _constrainedIntent(50 ether);
        Token[] memory tokensOut = new Token[](2);
        tokensOut[0] = intent.tokensOut[0];
        tokensOut[1] = _erc20(address(s_tokenIn), 10 ether); // never delivered
        intent.tokensOut = tokensOut;
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 60 ether, s_recipient); // first minimum clears

        // it should revert with AmountTooLow
        vm.expectRevert(
            abi.encodeWithSelector(EphemeralIntentExecutor.AmountTooLow.selector, tokensOut[1], 0, 10 ether)
        );
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheDeltaIsBelowTheMinimum() external {
        Intent memory intent = _constrainedIntent(50 ether);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 40 ether, s_recipient);

        // it should revert with AmountTooLow
        vm.expectRevert(
            abi.encodeWithSelector(
                EphemeralIntentExecutor.AmountTooLow.selector, intent.tokensOut[0], 40 ether, 50 ether
            )
        );
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheRouteDeliversToTheExecutorInstead() external {
        Intent memory intent = _constrainedIntent(50 ether);
        address predicted = _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 60 ether, predicted); // wrong receiver

        // it should revert with AmountTooLow
        vm.expectRevert(
            abi.encodeWithSelector(EphemeralIntentExecutor.AmountTooLow.selector, intent.tokensOut[0], 0, 50 ether)
        );
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheOutcomeIsAMintedNFT() external {
        // A freshly created position NFT: the id is unknowable at commit time, so the
        // 721 out-entry commits a minimum COUNT, not a tokenId.
        MockERC721 nft = new MockERC721("Position", "POS");
        Intent memory intent = _constrainedIntent(1 ether);
        intent.tokensOut[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(nft), uint256(1)) });
        _fund(intent, 100 ether);
        nft.mint(address(s_router), 42); // id decided at execution time
        s_router.setOutNFT(address(nft), 42, s_recipient);

        _execute(intent, hex"beefcafe");

        // it should satisfy the count minimum with whatever id arrived
        assertEq(nft.ownerOf(42), s_recipient);
        assertEq(nft.balanceOf(s_recipient), 1);
    }

    function test_WhenTheRecipientBalanceDecreases() external {
        Intent memory intent = _constrainedIntent(1 ether);
        _fund(intent, 100 ether);
        s_tokenOut.mint(s_recipient, 100 ether);
        vm.prank(s_recipient);
        s_tokenOut.approve(address(s_router), 60 ether);
        s_router.setDrain(address(s_tokenOut), s_recipient, 60 ether);

        // it should revert with AmountTooLow, not a Panic
        vm.expectRevert(
            abi.encodeWithSelector(EphemeralIntentExecutor.AmountTooLow.selector, intent.tokensOut[0], 0, 1 ether)
        );
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTokensOutIsEmpty() external {
        Intent memory intent = _constrainedIntent(1 ether);
        intent.tokensOut = new Token[](0);
        _fund(intent, 100 ether);

        // it should revert with Unconstrained — no floor means unconstrained theft
        vm.expectRevert(EphemeralIntentExecutor.Unconstrained.selector);
        _execute(intent, hex"beefcafe");
    }

    function test_WhenAMinimumIsZero() external {
        Intent memory intent = _constrainedIntent(0);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether, s_recipient);

        // it should revert with Unconstrained — a zero minimum enforces nothing
        vm.expectRevert(EphemeralIntentExecutor.Unconstrained.selector);
        _execute(intent, hex"beefcafe");
    }

    function test_WhenTheKeeperIsZero() external {
        Intent memory intent = _constrainedIntent(1 ether);
        intent.keeper = address(0);
        intent.keeperFee = _fee(address(s_tokenIn), 5 ether, 0);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether, s_recipient);
        address anyone = vm.addr(9);

        vm.prank(anyone);
        s_factory.executeIntent(intent, hex"beefcafe", new Token[](0));

        // it should let any caller route against the floor and pay them the fee
        assertEq(s_tokenOut.balanceOf(s_recipient), 1 ether);
        assertEq(s_tokenIn.balanceOf(anyone), 5 ether);
    }

    function test_WhenTheCallerIsNotTheKeeper() external {
        Intent memory intent = _constrainedIntent(1 ether);
        _fund(intent, 100 ether);
        s_router.setOut(address(s_tokenOut), 1 ether, s_recipient);

        // it should revert with NotKeeper
        vm.prank(vm.addr(9));
        vm.expectRevert(EphemeralIntentExecutor.NotKeeper.selector);
        s_factory.executeIntent(intent, hex"beefcafe", new Token[](0));

        // it should execute for the keeper
        _execute(intent, hex"beefcafe");
        assertEq(s_tokenOut.balanceOf(s_recipient), 1 ether);
    }
}

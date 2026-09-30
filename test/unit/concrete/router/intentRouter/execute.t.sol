// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent } from "../../../../../src/interfaces/IIntentRouter.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { MockERC1155 } from "../../../../mocks/MockERC1155.sol";
import { MockERC721 } from "../../../../mocks/MockERC721.sol";
import { WeirollPlanner } from "../../../../utils/WeirollPlanner.sol";
import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";
import { VM } from "enso-weiroll/VM.sol";
import { IERC1271 } from "openzeppelin-contracts/interfaces/IERC1271.sol";
import { IERC20Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/// A contract wallet that accepts its signer's ECDSA signatures over any hash.
contract ERC1271Wallet is IERC1271 {
    address public immutable signer;

    constructor(address signer_) {
        signer = signer_;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        return err == ECDSA.RecoverError.NoError && recovered == signer ? IERC1271.isValidSignature.selector : bytes4(0);
    }
}

/// Called from inside a route: attempts to reenter execute and records the error.
contract Reenterer {
    IntentRouter public immutable router;
    bytes4 public lastError;

    constructor(IntentRouter router_) {
        router = router_;
    }

    function hit() external {
        Intent memory intent;
        try router.execute(intent, "", "") { }
        catch (bytes memory err) {
            lastError = bytes4(err);
        }
    }
}

/// Revert tests sign before `vm.expectRevert`: signing reads `hash()` from the router, and
/// the expectation must attach to the execute call, not to that view.
contract IntentRouter_Execute_Unit_Concrete_Test is IntentRouter_Unit_Concrete_Test {
    function test_WhenTheCallerIsNotTheKeeper() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);

        // it should revert with NotKeeper
        vm.prank(s_owner);
        vm.expectRevert(IntentRouter.NotKeeper.selector);
        s_router.execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheChainIdDoesNotMatch() external {
        Intent memory intent = _intent();
        intent.chainId = 999;
        bytes memory signature = _sign(intent);

        // it should revert with WrongChain
        vm.expectRevert(IntentRouter.WrongChain.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenExecutedBeforeStart() external {
        Intent memory intent = _intent();
        intent.start = uint64(block.timestamp + 1 hours);
        bytes memory signature = _sign(intent);

        // it should revert with TooEarly
        vm.expectRevert(IntentRouter.TooEarly.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenExecutedAfterTheDeadline() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        vm.warp(intent.deadline + 1);

        // it should revert with Expired
        vm.expectRevert(IntentRouter.Expired.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheSignatureIsNotTheOwners() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(0xB0B, intent);

        // it should revert with InvalidSignature
        vm.expectRevert(IntentRouter.InvalidSignature.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheIntentIsTamperedAfterSigning() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        intent.recipient = s_keeper;

        // it should revert with InvalidSignature
        vm.expectRevert(IntentRouter.InvalidSignature.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_keeper, 50 ether));
    }

    function test_WhenTheNonceWasAlreadyUsed() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        bytes memory route = _transferRoute(address(s_tokenOut), s_recipient, 50 ether);
        _execute(intent, signature, route);

        // it should revert with NonceUsed
        vm.expectRevert(IntentRouter.NonceUsed.selector);
        _execute(intent, signature, route);
    }

    function test_WhenTheNonceWasCancelled() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        vm.prank(s_owner);
        s_router.cancel(intent.nonce);

        // it should revert with NonceUsed
        vm.expectRevert(IntentRouter.NonceUsed.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheOwnerIsAContractWallet() external {
        ERC1271Wallet wallet = new ERC1271Wallet(vm.addr(0xC0FFEE));
        s_tokenIn.mint(address(wallet), 100 ether);
        vm.prank(address(wallet));
        s_tokenIn.approve(address(s_router), 100 ether);
        Intent memory intent = _intent();
        intent.owner = address(wallet);
        bytes memory route = _transferRoute(address(s_tokenOut), s_recipient, 50 ether);

        // a signature the wallet does not recognise is still rejected
        bytes memory bad = _sign(0xB0B, intent);
        vm.expectRevert(IntentRouter.InvalidSignature.selector);
        _execute(intent, bad, route);

        // it should accept an ERC-1271 signature
        _execute(intent, _sign(0xC0FFEE, intent), route);
        assertEq(s_tokenIn.balanceOf(address(wallet)), 0);
        assertEq(s_tokenOut.balanceOf(s_recipient), 50 ether);
    }

    function test_WhenTheOwnerHasCodeButSignsWithItsKey() external {
        // An EIP-7702 style account: code at the address, but the key still signs.
        vm.etch(s_owner, hex"00");
        Intent memory intent = _intent();

        // it should accept the ECDSA signature
        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
        assertEq(s_tokenOut.balanceOf(s_recipient), 50 ether);
    }

    function test_WhenTheKeeperSuppliesTheRoute() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        s_tokenOut.mint(s_recipient, 100 ether); // pre-existing balance must not count

        // it should emit IntentExecuted
        vm.expectEmit(address(s_router));
        emit IntentRouter.IntentExecuted(s_owner, intent.nonce);

        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 60 ether));

        // it should pull tokensIn from the owner into shortcuts
        assertEq(s_tokenIn.balanceOf(s_owner), 900 ether);
        assertEq(s_tokenIn.balanceOf(s_shortcuts), 100 ether);

        // it should run the keeper's route
        // it should measure the delta at the recipient
        assertEq(s_tokenOut.balanceOf(s_recipient), 160 ether);

        // it should consume the nonce
        assertEq(s_router.nonceBitmap(s_owner, 0), 1);
    }

    function test_WhenTheRouteIsCommitted() external {
        Intent memory intent = _intent();
        intent.route = _transferRoute(address(s_tokenOut), s_recipient, 7 ether);
        intent.tokensOut = new Token[](0);

        // it should run the committed route and ignore the keeper's bytes
        // it should execute without an outcome floor
        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 1 ether));
        assertEq(s_tokenOut.balanceOf(s_recipient), 7 ether);
    }

    function test_WhenTheCommittedRouteMissesTheFloor() external {
        Intent memory intent = _intent();
        intent.route = _transferRoute(address(s_tokenOut), s_recipient, 7 ether);
        bytes memory signature = _sign(intent);

        // it should revert with AmountTooLow
        vm.expectRevert(
            abi.encodeWithSelector(IntentRouter.AmountTooLow.selector, intent.tokensOut[0], 7 ether, 50 ether)
        );
        _execute(intent, signature, "");
    }

    function test_WhenTheKeeperSuppliesTheRouteAndTokensOutIsEmpty() external {
        Intent memory intent = _intent();
        intent.tokensOut = new Token[](0);
        bytes memory signature = _sign(intent);

        // it should revert with Unconstrained
        vm.expectRevert(IntentRouter.Unconstrained.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenAMinimumIsZero() external {
        Intent memory intent = _intent();
        intent.tokensOut[0] = _erc20(address(s_tokenOut), 0);
        bytes memory signature = _sign(intent);

        // it should revert with Unconstrained
        vm.expectRevert(IntentRouter.Unconstrained.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheDeltaIsBelowTheMinimum() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);

        // it should revert with AmountTooLow
        vm.expectRevert(
            abi.encodeWithSelector(IntentRouter.AmountTooLow.selector, intent.tokensOut[0], 40 ether, 50 ether)
        );
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 40 ether));
    }

    function test_WhenAnyTokenOutMissesItsMinimum() external {
        Intent memory intent = _intent();
        Token[] memory tokensOut = new Token[](2);
        tokensOut[0] = intent.tokensOut[0];
        tokensOut[1] = _erc20(address(s_tokenIn), 10 ether); // never delivered
        intent.tokensOut = tokensOut;
        bytes memory signature = _sign(intent);

        // it should revert with AmountTooLow
        vm.expectRevert(abi.encodeWithSelector(IntentRouter.AmountTooLow.selector, tokensOut[1], 0, 10 ether));
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 60 ether)); // first clears
    }

    function test_WhenTheRecipientBalanceDecreases() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);
        s_tokenOut.mint(s_recipient, 100 ether);
        vm.prank(s_recipient);
        s_tokenOut.approve(s_shortcuts, 60 ether);

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](3);
        commands[0] =
            WeirollPlanner.buildCommand(IERC20.transferFrom.selector, 0x01, 0x000102ffffff, 0xff, address(s_tokenOut));
        state[0] = abi.encode(s_recipient);
        state[1] = abi.encode(s_shortcuts);
        state[2] = abi.encode(60 ether);

        // it should revert with AmountTooLow, not a Panic
        vm.expectRevert(abi.encodeWithSelector(IntentRouter.AmountTooLow.selector, intent.tokensOut[0], 0, 50 ether));
        _execute(intent, signature, _shortcut(commands, state));
    }

    function test_WhenTokenOutIsNative() external {
        Intent memory intent = _intent();
        intent.tokensOut[0] = _native(1 ether);
        vm.deal(s_shortcuts, 2 ether);

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);
        commands[0] = WeirollPlanner.buildCommand(bytes4(0), 0x03, 0x00ffffffffff, 0xff, s_recipient);
        state[0] = abi.encode(2 ether);

        _execute(intent, _shortcut(commands, state));

        // it should measure the native delta at the recipient
        assertEq(s_recipient.balance, 2 ether);
    }

    function test_WhenTheOutcomeIsAMintedNFT() external {
        // A freshly created position NFT: the id is unknowable at signing time, so the
        // 721 out-entry commits a minimum COUNT, not a tokenId.
        MockERC721 nft = new MockERC721("Position", "POS");
        Intent memory intent = _intent();
        intent.tokensOut[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(nft), uint256(1)) });

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](2);
        commands[0] = WeirollPlanner.buildCommand(nft.mint.selector, 0x01, 0x0001ffffffff, 0xff, address(nft));
        state[0] = abi.encode(s_recipient);
        state[1] = abi.encode(uint256(42)); // id decided at execution time

        _execute(intent, _shortcut(commands, state));

        // it should satisfy the count minimum with whatever id arrived
        assertEq(nft.ownerOf(42), s_recipient);
        assertEq(nft.balanceOf(s_recipient), 1);
    }

    function test_WhenTheOutcomeIsAnERC1155() external {
        MockERC1155 nft = new MockERC1155("uri");
        Intent memory intent = _intent();
        intent.tokensOut[0] =
            Token({ tokenType: TokenType.ERC1155, data: abi.encode(address(nft), uint256(9), uint256(3)) });

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](3);
        commands[0] = WeirollPlanner.buildCommand(nft.mint.selector, 0x01, 0x000102ffffff, 0xff, address(nft));
        state[0] = abi.encode(s_recipient);
        state[1] = abi.encode(uint256(9));
        state[2] = abi.encode(uint256(3));

        _execute(intent, _shortcut(commands, state));

        // it should measure the id balance at the recipient
        assertEq(nft.balanceOf(s_recipient, 9), 3);
    }

    function test_WhenTokenInIsNative() external {
        Intent memory intent = _intent();
        intent.tokensIn[0] = _native(1 ether);
        bytes memory signature = _sign(intent);

        // it should revert with UnsupportedTokenType
        vm.expectRevert(abi.encodeWithSelector(IntentRouter.UnsupportedTokenType.selector, TokenType.Native));
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTokenInIsAnNFT() external {
        MockERC721 nft = new MockERC721("Position", "POS");
        nft.mint(s_owner, 7);
        vm.prank(s_owner);
        nft.approve(address(s_router), 7);
        Intent memory intent = _intent();
        intent.tokensIn[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(nft), uint256(7)) });

        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));

        // it should pull the committed tokenId from the owner
        assertEq(nft.ownerOf(7), s_shortcuts);
        assertEq(s_tokenIn.balanceOf(s_owner), 1000 ether); // nothing else moved
    }

    function test_WhenTokenInIsAnERC1155() external {
        MockERC1155 nft = new MockERC1155("uri");
        nft.mint(s_owner, 9, 5);
        vm.prank(s_owner);
        nft.setApprovalForAll(address(s_router), true);
        Intent memory intent = _intent();
        intent.tokensIn[0] =
            Token({ tokenType: TokenType.ERC1155, data: abi.encode(address(nft), uint256(9), uint256(5)) });

        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));

        // it should pull the committed amount of the id from the owner
        assertEq(nft.balanceOf(s_shortcuts, 9), 5);
        assertEq(nft.balanceOf(s_owner, 9), 0);
    }

    function test_WhenTheOwnerHasNotApproved() external {
        vm.prank(s_owner);
        s_tokenIn.approve(address(s_router), 0);
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);

        // it should revert on the pull
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(s_router), 0, 100 ether)
        );
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheIntentFeeIsSet() external {
        Intent memory intent = _intent();
        intent.keeperFee = _fee(address(s_tokenIn), 5 ether, 1 ether);

        _execute(intent, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));

        // it should pull the fee from the owner to the keeper
        assertEq(s_tokenIn.balanceOf(s_keeper), 5 ether);
        assertEq(s_tokenIn.balanceOf(s_shortcuts), 100 ether);

        // it should ignore the refund fee
        assertEq(s_tokenIn.balanceOf(s_owner), 895 ether);
    }

    function test_WhenTheIntentFeeIsNative() external {
        Intent memory intent = _intent();
        intent.keeperFee = _fee(address(0), 1 ether, 0);
        bytes memory signature = _sign(intent);

        // it should revert with UnsupportedTokenType
        vm.expectRevert(abi.encodeWithSelector(IntentRouter.UnsupportedTokenType.selector, TokenType.Native));
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 50 ether));
    }

    function test_WhenTheRouteReverts() external {
        Intent memory intent = _intent();
        bytes memory signature = _sign(intent);

        // it should bubble the revert
        vm.expectPartialRevert(VM.ExecutionFailed.selector);
        _execute(intent, signature, _transferRoute(address(s_tokenOut), s_recipient, 2_000_000 ether)); // > inventory
    }

    function test_WhenAShortcutReentersExecute() external {
        Reenterer reenterer = new Reenterer(s_router);
        Intent memory intent = _intent();

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);
        commands[0] =
            WeirollPlanner.buildCommand(reenterer.hit.selector, 0x01, 0xffffffffffff, 0xff, address(reenterer));
        commands[1] =
            WeirollPlanner.buildCommand(IERC20.transfer.selector, 0x01, 0x0001ffffffff, 0xff, address(s_tokenOut));
        state[0] = abi.encode(s_recipient);
        state[1] = abi.encode(50 ether);

        _execute(intent, _shortcut(commands, state));

        // it should revert with NotKeeper
        assertEq(reenterer.lastError(), IntentRouter.NotKeeper.selector);
        assertEq(s_tokenOut.balanceOf(s_recipient), 50 ether);
    }
}

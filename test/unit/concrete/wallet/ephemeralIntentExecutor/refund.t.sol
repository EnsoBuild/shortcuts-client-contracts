// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/libraries/TokenLib.sol";
import { Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockDirtyBoolERC20 } from "../../../../mocks/MockDirtyBoolERC20.sol";
import { MockERC1155 } from "../../../../mocks/MockERC1155.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockERC721 } from "../../../../mocks/MockERC721.sol";
import { MockRevertingERC20 } from "../../../../mocks/MockRevertingERC20.sol";
import { EphemeralIntentExecutor_Unit_Concrete_Test } from "./EphemeralIntentExecutor.t.sol";

contract EphemeralIntentExecutor_Refund_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    function test_WhenTheDeadlineHasPassed() external {
        Intent memory intent = _intent();
        intent.keeperFee = _erc20(address(s_tokenIn), 5 ether);
        address predicted = _fund(intent, 100 ether);

        MockERC20 extra = new MockERC20("Extra", "EXT");
        extra.mint(predicted, 42 ether);
        MockRevertingERC20 reverting = new MockRevertingERC20();

        vm.warp(intent.deadline + 1);

        Token[] memory sweep = new Token[](2);
        sweep[0] = _erc20(address(reverting), 0);
        sweep[1] = _erc20(address(extra), 0);
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

    function test_WhenNFTsAreKeeperListed() external {
        Intent memory intent = _intent();
        address predicted = _fund(intent, 100 ether);

        MockERC721 nft = new MockERC721("NFT", "NFT");
        nft.mint(predicted, 7);
        MockERC1155 multi = new MockERC1155("uri");
        multi.mint(predicted, 9, 3);

        vm.warp(intent.deadline + 1);

        Token[] memory sweep = new Token[](2);
        sweep[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(nft), uint256(7)) });
        sweep[1] = Token({ tokenType: TokenType.ERC1155, data: abi.encode(address(multi), uint256(9), uint256(0)) });
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", sweep);

        // it should sweep keeper-listed NFTs to the refund recipient
        assertEq(nft.ownerOf(7), s_user);
        assertEq(multi.balanceOf(s_user, 9), 3);
    }

    /// forge-config: default.isolate = true
    function test_WhenTheTriggerDataIsMalformed() external {
        Intent memory intent = _intent();
        intent.triggers[0] = Token({ tokenType: TokenType.ERC20, data: hex"deadbeef" }); // undecodably short
        address predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, 100 ether);
        vm.warp(intent.deadline + 1);

        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        // it should skip the malformed trigger and complete the lifecycle
        assertEq(predicted.code.length, 0);
        assertEq(s_tokenIn.balanceOf(predicted), 100 ether); // skipped in place, not lost

        // it should recover the skipped asset with a second transaction
        Token[] memory sweep = new Token[](1);
        sweep[0] = _erc20(address(s_tokenIn), 0);
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", sweep);
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    function test_WhenTheTriggerAddressWordIsDirty() external {
        Intent memory intent = _intent();
        bytes32 dirty = bytes32(uint256(uint160(address(s_tokenIn))) | (uint256(0xBAD) << 160));
        intent.triggers[0] = Token({ tokenType: TokenType.ERC20, data: abi.encodePacked(dirty, uint256(100 ether)) });
        address predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, 100 ether);
        vm.warp(intent.deadline + 1);

        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        // it should truncate the dirty word and fully refund
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    function test_WhenATriggerTokenReturnsADirtyBool() external {
        MockDirtyBoolERC20 dirty = new MockDirtyBoolERC20();
        Intent memory intent = _intent();
        intent.triggers[0] = _erc20(address(dirty), 100 ether);
        address predicted = s_factory.getAddress(intent);
        dirty.mint(predicted, 100 ether);
        vm.warp(intent.deadline + 1);

        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        // it should tolerate the non-canonical return and still deliver the refund
        assertEq(dirty.balanceOf(s_user), 100 ether);
    }

    function test_WhenTheRefundRecipientIsZero() external {
        Intent memory intent = _intent();
        intent.refundRecipient = address(0);
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 1 ether);
        vm.warp(intent.deadline + 1);
        uint256 keeperNativeBefore = s_keeper.balance;

        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        // it should substitute the keeper as beneficiary — nothing burned or stranded
        assertEq(s_tokenIn.balanceOf(s_keeper), 100 ether);
        assertEq(s_keeper.balance, keeperNativeBefore + 1 ether);
        assertEq(address(0).balance, 0);
    }

    function test_WhenTheFeeTokenIsMalformed() external {
        Intent memory intent = _intent();
        intent.chainId = 999; // wrong-chain recovery — fee is best-effort here
        intent.keeperFee = Token({ tokenType: TokenType.ERC20, data: hex"deadbeef" }); // undecodable
        _fund(intent, 100 ether);

        _execute(intent, "");

        // it should skip the fee and still refund
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    function test_WhenTheFeeTokenIsCodeless() external {
        Intent memory intent = _intent();
        intent.chainId = 999;
        intent.keeperFee = _erc20(address(0xDEAD), 5 ether); // no code at this address
        _fund(intent, 100 ether);

        _execute(intent, "");

        // it should skip the fee and still refund
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }

    function test_WhenExecutedOnTheWrongChain() external {
        Intent memory intent = _intent();
        intent.chainId = 999; // committed for another chain
        intent.start = uint64(block.timestamp + 1 hours); // gates must not apply
        address predicted = _fund(intent, 100 ether);
        vm.deal(predicted, 1 ether);

        _execute(intent, "");

        // it should sweep immediately without waiting for the gates
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);

        // it should sweep native via selfdestruct
        assertEq(s_user.balance, 1 ether);
    }
}

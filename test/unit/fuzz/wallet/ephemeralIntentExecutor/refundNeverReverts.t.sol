// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent, KeeperFee } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import {
    EphemeralIntentExecutor_Unit_Concrete_Test
} from "../../../concrete/wallet/ephemeralIntentExecutor/EphemeralIntentExecutor.t.sol";

/// The codebase's central invariant, in executable form: no opcode reachable from
/// _refund may revert. A revert on a refund branch is a permanent brick — no branch
/// of the constructor terminates, selfdestruct never runs, the address can only ever
/// host this one initcode, and the deposit is unrecoverable forever.
contract EphemeralIntentExecutor_RefundNeverReverts_Unit_Fuzz_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RefundNeverReverts_committedTrigger(bytes memory data, uint8 tokenTypeSeed) external {
        Intent memory intent = _intent();
        intent.triggers[0] = Token({ tokenType: TokenType(tokenTypeSeed % 4), data: data });
        address predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, 100 ether);
        vm.deal(predicted, 1 ether);
        vm.warp(intent.deadline + 1);

        // it must not revert, whatever the committed trigger bytes are
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        // it must complete the lifecycle: account deleted, native swept
        assertEq(predicted.code.length, 0);
        assertEq(s_user.balance, 1 ether);
        // funded ERC20 either swept (well-formed trigger) or skipped in place — never lost
        assertEq(s_tokenIn.balanceOf(s_user) + s_tokenIn.balanceOf(predicted), 100 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RefundNeverReverts_keeperFee(address feeToken, uint256 refundFee) external {
        Intent memory intent = _intent();
        intent.keeperFee = KeeperFee({ token: feeToken, intentFee: 0, refundFee: refundFee });
        address predicted = _fund(intent, 100 ether);
        vm.warp(intent.deadline + 1);

        // it must not revert, whatever the fee token address — codeless, an EOA, a
        // precompile, a contract without balanceOf — or the committed amount
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        assertEq(predicted.code.length, 0);
        // a well-formed fuzzed fee may legitimately pay the keeper; nothing may vanish
        assertEq(s_tokenIn.balanceOf(s_user) + s_tokenIn.balanceOf(s_keeper), 100 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RefundNeverReverts_wrongChain(bytes memory data, uint8 tokenTypeSeed) external {
        Intent memory intent = _intent();
        intent.chainId = 999; // wrong-chain recovery branch
        intent.triggers[0] = Token({ tokenType: TokenType(tokenTypeSeed % 4), data: data });
        address predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, 100 ether);

        // it must not revert on the wrong-chain branch either
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", new Token[](0));

        assertEq(predicted.code.length, 0);
        assertEq(s_tokenIn.balanceOf(s_user) + s_tokenIn.balanceOf(predicted), 100 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SweepListNeverReverts(bytes memory data, uint8 tokenTypeSeed) external {
        Intent memory intent = _intent();
        address predicted = _fund(intent, 100 ether);
        vm.warp(intent.deadline + 1);
        Token[] memory sweep = new Token[](1);
        sweep[0] = Token({ tokenType: TokenType(tokenTypeSeed % 4), data: data });

        // a keeper-supplied entry must never block the exit
        vm.prank(s_keeper);
        s_factory.executeIntent(intent, "", sweep);

        assertEq(predicted.code.length, 0);
        assertEq(s_tokenIn.balanceOf(s_user), 100 ether);
    }
}

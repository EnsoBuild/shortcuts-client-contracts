// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Asset, Codes, Constraints, Intent, Refund } from "../../../../../src/interfaces/IIntent.sol";
import { EphemeralIntentExecutor } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import {
    EphemeralIntentExecutor_Unit_Concrete_Test
} from "../../../concrete/wallet/ephemeralIntentExecutor/EphemeralIntentExecutor.t.sol";

/// The codebase's central invariant, in executable form: no opcode reachable from a refund may
/// revert. A revert on a refund branch is a permanent brick: no branch of the constructor
/// terminates, selfdestruct never runs, and the deposit is unrecoverable.
contract EphemeralIntentExecutor_RefundNeverReverts_Unit_Fuzz_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;

    function _swapIntent() internal view returns (Intent memory) {
        Constraints memory c = _swap(
            address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0.5 ether, Codes.DRAIN
        );
        return _intent(c, s_user, s_keeper);
    }

    function _refundAndCheck(Intent memory intent, Token[] memory sweep) internal {
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        vm.deal(at, 1 ether);
        vm.warp(intent.deadline + 1);

        Execution memory e = _execution(intent);
        e.sweep = sweep;
        uint256 keeperNative = s_keeper.balance;
        _run(s_keeper, root, e);

        // it must complete the lifecycle: account deleted, native to the owner or paid as a fee
        assertEq(at.code.length, 0, "terminated");
        assertEq(s_user.balance + (s_keeper.balance - keeperNative), 1 ether, "native conserved");
        // funded tokens are swept, paid as a fee, or skipped in place; never lost
        assertEq(
            s_tokenIn.balanceOf(s_user) + s_tokenIn.balanceOf(s_keeper) + s_tokenIn.balanceOf(at), DEPOSIT, "conserved"
        );
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RefundNeverReverts_inputs(
        uint16 inputAsset,
        uint16 refundAsset,
        uint8 kind,
        address token,
        uint256 refundFee,
        uint8 threshold
    )
        external
    {
        Intent memory intent = _swapIntent();
        Constraints memory c = intent.constraints;
        // A committed rule input and refund entry whose assets may be out of range, of any kind,
        // at any address, under any threshold.
        c.assets[0] = Asset({ kind: kind, chainId: block.chainid, token: token, id: 0 });
        c.rules[0].inputs[0].asset = inputAsset % 4;
        c.rules[0].threshold = threshold;
        c.refunds = new Refund[](1);
        c.refunds[0] = Refund({ asset: refundAsset % 4, fee: refundFee });
        _refundAndCheck(intent, new Token[](0));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RefundNeverReverts_sweepList(bytes memory data, uint8 tokenTypeSeed) external {
        Token[] memory sweep = new Token[](1);
        sweep[0] = Token({ tokenType: TokenType(tokenTypeSeed % 4), data: data });
        _refundAndCheck(_swapIntent(), sweep);
    }

    /// Branch selection reverts only for a proof that doesn't verify, never for anything else.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BadProof_OnlyInvalidProof(bytes32 sibling) external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        vm.warp(intent.deadline + 1);

        Execution memory e = _execution(intent);
        e.proof = new bytes32[](1);
        e.proof[0] = sibling;
        vm.expectRevert(EphemeralIntentExecutor.InvalidProof.selector);
        _run(s_keeper, root, e);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../../src/intent/BridgeGuardian.sol";
import { Obligation } from "../../src/interfaces/IIntentGuardian.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { Vm } from "forge-std/Vm.sol";

/// Signs BridgeGuardian subsidies the way a payer does: a Permit2 witness transfer of the fee, with
/// the bridge call it pays for as the witness (an Across Deposit or a CCTP Burn).
library Subsidies {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    ISignatureTransfer internal constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 internal constant PERMIT_DEPOSIT_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,Deposit witness)Deposit(address caller,bytes32 intentHash,address refund,address recipient,uint256 chainId,address output,uint256 amount,uint256 outputAmount,uint32 fillDeadline)TokenPermissions(address token,uint256 amount)"
    );
    bytes32 internal constant PERMIT_BURN_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,Burn witness)Burn(address caller,bytes32 intentHash,address recipient,uint256 chainId,uint256 amount,uint256 maxFee,uint32 minFinalityThreshold)TokenPermissions(address token,uint256 amount)"
    );

    /// The CCTP burn a subsidy pays for, as the guardian hashes it.
    struct Burn {
        address caller;
        bytes32 intentHash;
        Obligation obligation;
        uint256 amount;
        uint256 maxFee;
        uint32 minFinalityThreshold;
    }

    /// The deposit a subsidy pays for, as the guardian hashes it.
    struct Deposit {
        address caller;
        bytes32 intentHash;
        Obligation obligation;
        uint256 amount;
        uint256 outputAmount;
        uint32 fillDeadline;
    }

    function sign(
        BridgeGuardian guardian,
        uint256 key,
        address token,
        uint256 fee,
        uint256 nonce,
        Deposit memory d
    )
        internal
        view
        returns (BridgeGuardian.Subsidy memory)
    {
        return _sign(guardian, key, token, fee, nonce, PERMIT_DEPOSIT_TYPEHASH, witness(guardian, d));
    }

    function sign(
        BridgeGuardian guardian,
        uint256 key,
        address token,
        uint256 fee,
        uint256 nonce,
        Burn memory b
    )
        internal
        view
        returns (BridgeGuardian.Subsidy memory)
    {
        return _sign(guardian, key, token, fee, nonce, PERMIT_BURN_TYPEHASH, witness(guardian, b));
    }

    function witness(BridgeGuardian guardian, Deposit memory d) internal view returns (bytes32) {
        Obligation memory o = d.obligation;
        return keccak256(
            abi.encode(
                guardian.DEPOSIT_TYPEHASH(),
                d.caller,
                d.intentHash,
                o.refund,
                o.recipient,
                o.chainId,
                o.token,
                d.amount,
                d.outputAmount,
                d.fillDeadline
            )
        );
    }

    function witness(BridgeGuardian guardian, Burn memory b) internal view returns (bytes32) {
        Obligation memory o = b.obligation;
        return keccak256(
            abi.encode(
                guardian.BURN_TYPEHASH(),
                b.caller,
                b.intentHash,
                o.recipient,
                o.chainId,
                b.amount,
                b.maxFee,
                b.minFinalityThreshold
            )
        );
    }

    function _sign(
        BridgeGuardian guardian,
        uint256 key,
        address token,
        uint256 fee,
        uint256 nonce,
        bytes32 typehash,
        bytes32 witness_
    )
        private
        view
        returns (BridgeGuardian.Subsidy memory)
    {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitted = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, token, fee));
        bytes32 structHash = keccak256(abi.encode(typehash, permitted, address(guardian), nonce, deadline, witness_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = VM.sign(key, digest);
        return BridgeGuardian.Subsidy({
            payer: VM.addr(key), fee: fee, nonce: nonce, deadline: deadline, signature: abi.encodePacked(r, s, v)
        });
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";

import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";

import { SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS } from "account-abstraction-v7/core/Helpers.sol";
import { PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { console2 } from "forge-std/Test.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

contract SignaturePaymaster_ValidatePaymasterUserOp_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    address payable private constant ENSO_BACKEND = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // Anvil 0
    bytes32 private constant ENSO_BACKEND_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function test_RevertWhen_CallerIsNotEntryPoint() external {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = bytes32(0);
        uint256 maxCost = 0;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(SignaturePaymaster.InvalidEntryPoint.selector, s_account3));
        vm.prank(s_account3);
        s_signaturePaymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    modifier whenCallerIsEntryPoint() {
        vm.startPrank(address(s_entryPoint));
        _;
        vm.stopPrank();
    }

    function test_WhenRecoveredAddressIsNotValidSigner() external whenCallerIsEntryPoint {
        // *** Arrange ***
        PackedUserOperation memory userOp = _getUserOpWithPaymasterAndDataSignedBy(ENSO_BACKEND_PK);

        bytes32 userOpHash = bytes32(0);
        uint256 maxCost = 0;

        // *** Act & Assert ***
        (bytes memory context, uint256 validationData) =
            s_signaturePaymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        // it should return failure validation data
        assertEq(context, "");
        assertEq(validationData, 2_468_256_835_981_810_524_734_091_104_738_943_961_158_936_514_733_389_450_955_456_513);
    }

    function test_WhenRecoveredAddressIsValidSigner() external whenCallerIsEntryPoint {
        // *** Arrange ***
        // NOTE: set `ENSO_BACKEND` as valid signer
        vm.stopPrank();
        vm.prank(s_owner);
        s_signaturePaymaster.setSigner(ENSO_BACKEND, true);
        vm.startPrank(address(s_entryPoint));

        PackedUserOperation memory userOp = _getUserOpWithPaymasterAndDataSignedBy(ENSO_BACKEND_PK);

        bytes32 userOpHash = bytes32(0);
        uint256 maxCost = 0;

        // *** Act & Assert ***
        (bytes memory context, uint256 validationData) =
            s_signaturePaymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        // it should return success validation data
        assertEq(context, "");
        assertEq(validationData, 2_468_256_835_981_810_524_734_091_104_738_943_961_158_936_514_733_389_450_955_456_512);
    }

    function _getUserOpWithPaymasterAndDataSignedBy(bytes32 signerPk)
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        // --- UserOp Essential parameters ---
        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp);
        uint48 validAfter = uint48(block.timestamp + 5 seconds);
        uint128 paymasterVerificationGas = 0;
        uint128 paymasterPostOp = 0;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature = abi.encodePacked(
            address(s_signaturePaymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter
        );
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with signer's private key
        bytes32 pmdHash = s_signaturePaymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(signerPk), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;
    }
}

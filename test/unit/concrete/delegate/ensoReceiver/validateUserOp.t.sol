// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EIP7702EnsoShortcuts } from "../../../../../src/delegate/EIP7702EnsoShortcuts.sol";
import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS } from "account-abstraction-v7/core/Helpers.sol";
import { PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { console2 } from "forge-std/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalERC1271 {
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    function isValidSignature(
        bytes32, // hash
        bytes memory //  signature
    )
        public
        pure
        returns (bytes4 magicValue)
    {
        return EIP1271_MAGIC_VALUE;
    }
}

contract EnsoReceiver_ValidateUserOp_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test {
    struct ValidateUserOpParams {
        PackedUserOperation userOp;
        bytes32 userOpHash;
        uint256 missingAccountFunds;
    }

    function test_RevertWhen_CallerIsNotEntryPoint() external {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = bytes32(0);
        uint256 missingAccountFunds = 0;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_owner));
        vm.prank(s_owner);
        s_ensoReceiver.validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    modifier whenCallerIsEntryPoint() {
        vm.startPrank(address(s_entryPoint));
        _;
        vm.stopPrank();
    }

    modifier whenSignerIsEOA() {
        assertEq(s_signer, EOA_1);
        _;
    }

    function test_RevertWhen_NonceIsNotValid1() external whenCallerIsEntryPoint whenSignerIsEOA {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.UnorderedNonceNotSupported.selector, s_owner));
        s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );
    }

    function test_WhenNonceIsValid1() external whenCallerIsEntryPoint whenSignerIsEOA {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, false);
        uint256 validationData = s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );

        // it should return sigValidationSuccess
        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    modifier whenSignerIsEOA7702() {
        EIP7702EnsoShortcuts eip7702EnsoShortcuts = new EIP7702EnsoShortcuts();

        assertEq(address(s_signer).code.length == 0, true);
        vm.signAndAttachDelegation(address(eip7702EnsoShortcuts), uint256(s_signerPk));
        assertEq(address(s_signer).code.length > 0, true);
        _;
    }

    function test_RevertWhen_NonceIsNotValid2() external whenCallerIsEntryPoint whenSignerIsEOA7702 {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.UnorderedNonceNotSupported.selector, s_owner));
        s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );
    }

    function test_WhenNonceIsValid2() external whenCallerIsEntryPoint whenSignerIsEOA7702 {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, false);
        uint256 validationData = s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );

        // it should return sigValidationSuccess
        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    function test_WhenSignerIsNotERC1271() external whenCallerIsEntryPoint {
        // NOTE: force a different signer PK
        ValidateUserOpParams memory validateUserOpParams =
            _getValidateUserOpParamsSignedBy(keccak256(abi.encode(777)), false);
        uint256 validationData = s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );

        // it should return sigValidationFailed
        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    modifier whenSignerIsERC1271() {
        vm.stopPrank();

        vm.prank(s_deployer);
        MinimalERC1271 erc1271 = new MinimalERC1271();

        vm.prank(s_owner);
        s_ensoReceiver.setSigner(address(erc1271));
        s_signer = payable(address(erc1271));
        s_signerPk = bytes32(uint256(777)); // NOTE: vm.sign: private key cannot be 0

        vm.startPrank(address(s_entryPoint));
        _;
    }

    function test_RevertWhen_NonceIsNotValid3() external whenCallerIsEntryPoint whenSignerIsERC1271 {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, true);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.UnorderedNonceNotSupported.selector, s_owner));
        s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );
    }

    function test_WhenNonceIsValid3() external whenCallerIsEntryPoint whenSignerIsERC1271 {
        ValidateUserOpParams memory validateUserOpParams = _getValidateUserOpParamsSignedBy(s_signerPk, false);
        uint256 validationData = s_ensoReceiver.validateUserOp(
            validateUserOpParams.userOp, validateUserOpParams.userOpHash, validateUserOpParams.missingAccountFunds
        );

        // it should return sigValidationSuccess
        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    function _getValidateUserOpParamsSignedBy(
        bytes32 signerPk,
        bool isUnorderedNonce
    )
        internal
        view
        returns (ValidateUserOpParams memory validateUserOpParams)
    {
        PackedUserOperation memory userOp;

        userOp.nonce = isUnorderedNonce ? type(uint64).max : 0;

        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        bytes32 ethSignedUserOpHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(signerPk), ethSignedUserOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        validateUserOpParams.userOp = userOp;
        validateUserOpParams.userOpHash = userOpHash;
        validateUserOpParams.missingAccountFunds = 0;
    }
}

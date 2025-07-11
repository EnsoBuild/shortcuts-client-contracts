// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { IERC4337CloneInitializer } from "../factory/interfaces/IERC4337CloneInitializer.sol";
import { SignatureVerifier } from "../libraries/SignatureVerifier.sol";
import { IERC20, Withdrawable } from "../utils/Withdrawable.sol";
import { SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS } from "account-abstraction/core/Helpers.sol";
import { IAccount, PackedUserOperation } from "account-abstraction/interfaces/IAccount.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

contract EnsoReceiver is
    IAccount,
    IERC4337CloneInitializer,
    AbstractMultiSend,
    AbstractEnsoShortcuts,
    Withdrawable,
    Initializable
{
    using SignatureVerifier for bytes32;

    address public signer;
    address public entryPoint;

    event ShortcutExecutionSuccessful();
    event ShortcutExecutionFailed(bytes error);
    event NewSigner(address newSigner);
    event NewEntryPoint(address newEntryPoint);

    error InvalidSender(address sender);

    modifier onlyReceiverOrEntryPoint() {
        if (msg.sender != entryPoint && msg.sender != receiver) revert InvalidSender(msg.sender);
        _;
    }

    // @audit this modifier and the above could reuse logic
    // @audit error messages could be more descriptive, force you to look at the function modifier
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert InvalidSender(msg.sender);
        _;
    }

    function initialize(address receiver_, address signer_, address entryPoint_) external initializer {
        receiver = receiver_;
        signer = signer_;
        entryPoint = entryPoint_;
    }

    // @audit could entryPoint clear (sent to receiver) this contract of native token and tokens anytime, instead of
    // only the ones
    // involved in the data, is it ok?
    // @audit YES - will there be enough gas to withdraw token?
    // @audit no support for ERC721s, ERC1155s, etc.?
    function safeExecute(IERC20 token, bytes calldata data) external onlyReceiverOrEntryPoint {
        (bool success, bytes memory response) = address(this).call(data);
        if (success) {
            emit ShortcutExecutionSuccessful();
        } else {
            // if shortcut fails send funds to receiver
            emit ShortcutExecutionFailed(response);
            _withdrawToken(token);
        }
    }

    function updateSigner(address newSigner) external onlyReceiver {
        signer = newSigner;
        emit NewSigner(newSigner);
    }

    function updateEntryPoint(address newEntryPoint) external onlyReceiver {
        entryPoint = newEntryPoint;
        emit NewEntryPoint(newEntryPoint);
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 // missingAccountFunds
    )
        external
        view
        onlyEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        // _validateNonce(userOp.nonce); TODO: validate nonce?
        // @audit I'd say YES
        // @audit EntryPoint address is checked, but chainId should be too.
        // @audit userOp.nonce comes from `entryPoint.getNonce(entryPoint, key)`, what's the key?
        // `mapping(address => mapping(uint192 => uint256)) public nonceSequenceNumber;`
        // @audit invalid nonce must revert as SIG_VALIDATION_FAILED
    }

    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        internal
        view
        returns (uint256)
    {
        return userOpHash.isValidSig(signer, userOp.signature) ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
    }

    /// @notice Function to validate msg.sender.
    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        // only support self calls or calls from receiver
        if (msg.sender != address(this) && msg.sender != receiver) revert InvalidSender(msg.sender);
    }
}

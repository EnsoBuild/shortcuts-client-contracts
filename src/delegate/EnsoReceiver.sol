// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { IERC4337CloneInitializer } from "../factory/interfaces/IERC4337CloneInitializer.sol";
import { IERC20, Withdrawable } from "../utils/Withdrawable.sol";
import { SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS } from "account-abstraction/core/Helpers.sol";
import { IAccount, PackedUserOperation } from "account-abstraction/interfaces/IAccount.sol";

import { StdStorage, Test, console2, stdStorage } from "forge-std-1.9.7/Test.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

contract EnsoReceiver is
    IAccount,
    IERC4337CloneInitializer,
    AbstractMultiSend,
    AbstractEnsoShortcuts,
    Withdrawable,
    Initializable,
    ReentrancyGuardTransient
{
    address private _owner;
    address public signer;
    address public entryPoint;

    event ShortcutExecutionSuccessful();
    event ShortcutExecutionFailed(bytes error);
    event NewSigner(address newSigner);
    event NewEntryPoint(address newEntryPoint);

    error InvalidSender(address sender);
    error UnorderedNonceNotSupported();

    // for readability we use the same modifiers as the Ownable contract but this contract
    // does not allow the transferring of ownership, since the address is determinstically
    // deployed based on the owner
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyOwnerOrEntryPoint() {
        if (msg.sender != entryPoint && msg.sender != owner()) revert InvalidSender(msg.sender);
        _;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert InvalidSender(msg.sender);
        _;
    }

    function initialize(address owner_, address signer_, address entryPoint_) external initializer {
        _owner = owner_;
        signer = signer_;
        entryPoint = entryPoint_;
    }

    function safeExecute(IERC20 token, uint256 amount, bytes calldata data) external onlyOwnerOrEntryPoint {
        (bool success, bytes memory response) = address(this).call(data);
        if (success) {
            emit ShortcutExecutionSuccessful();
        } else {
            // if shortcut fails send funds to receiver
            emit ShortcutExecutionFailed(response);
            _withdrawToken(token, amount);
        }
    }

    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit NewSigner(newSigner);
    }

    function setEntryPoint(address newEntryPoint) external onlyOwner {
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
        _validateNonce(userOp.nonce);
    }

    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        internal
        view
        returns (uint256)
    {
        // First attempt ECDSA recovery to support EOAs and EIP-7702 accounts, which may have contract code but still
        // use standard ECDSA signatures.
        // If ECDSA recovery fails, fall back to ERC-1271 for traditional smart contract wallets.
        (address recovered, ECDSA.RecoverError errors,) = ECDSA.tryRecover(userOpHash, userOp.signature);
        console2.log("*** signer", signer);
        console2.log("*** recovered", recovered);
        console2.log("*** errros", uint8(errors));
        if (errors == ECDSA.RecoverError.NoError && recovered == signer) {
            return SIG_VALIDATION_SUCCESS;
        }
        bool isValid = SignatureChecker.isValidERC1271SignatureNow(signer, userOpHash, userOp.signature);
        console2.log("*** isValid", isValid);
        return isValid ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
    }

    function _validateNonce(uint256 nonce) internal pure {
        if (nonce == type(uint64).max) revert UnorderedNonceNotSupported();
    }

    /// @notice Override to include reentrancy guard
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        public
        payable
        override
        nonReentrant
        returns (bytes[] memory response)
    {
        return super.executeShortcut(accountId, requestId, commands, state);
    }

    /// @notice Override to include reentrancy guard
    function executeMultiSend(
        bytes32 accountId,
        bytes32 requestId,
        bytes memory transactions
    )
        public
        payable
        override
        nonReentrant
    {
        return super.executeMultiSend(accountId, requestId, transactions);
    }

    /// @notice Abstract override function to validate msg.sender.
    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        // only support self calls or calls from owner
        if (msg.sender != address(this) && msg.sender != owner()) revert InvalidSender(msg.sender);
    }

    /// @notice Abstract override function to return owner
    function owner() public view override returns (address) {
        return _owner;
    }

    /// @notice Abstract override function to check owner
    function _checkOwner() internal view override {
        if (msg.sender != owner()) revert InvalidSender(msg.sender);
    }
}

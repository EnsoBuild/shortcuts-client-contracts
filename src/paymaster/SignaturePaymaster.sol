// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { UserOperationLib } from "account-abstraction/core/UserOperationLib.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

contract SignaturePaymaster is IPaymaster, Ownable2Step {
    address private constant _NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IEntryPoint public entryPoint;
    mapping(address signer => bool isValid) validSigners;

    event SignerSet(address signer, bool isValid);

    error InvalidEntryPoint(address sender);
    error InsufficientFeeReceived(uint256 amount);
    error SignerIsAlreadySet(address signer, bool isValid);

    uint256 private constant PAYMASTER_VALIDATION_GAS_OFFSET = UserOperationLib.PAYMASTER_VALIDATION_GAS_OFFSET;
    uint256 private constant PAYMASTER_POSTOP_GAS_OFFSET = UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;
    uint256 private constant PAYMASTER_DATA_OFFSET = UserOperationLib.PAYMASTER_DATA_OFFSET;
    uint256 private constant VALID_UNTIL_OFFSET = PAYMASTER_DATA_OFFSET;
    uint256 private constant VALID_AFTER_OFFSET = VALID_UNTIL_OFFSET + 6; // uint48 = bytes6
    uint256 private constant SIGNATURE_OFFSET = VALID_AFTER_OFFSET + 6; // uint48 = bytes6

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert InvalidEntryPoint(msg.sender);
        _;
    }

    constructor(IEntryPoint entryPoint_, address owner_) Ownable(owner_) {
        entryPoint = entryPoint_;
    }

    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, // userOpHash
        uint256 // maxCost
    )
        external
        view
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) =
            parsePaymasterAndData(userOp.paymasterAndData);
        bytes32 messageHash = getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (address recovered,,) = ECDSA.tryRecover(ethSignedMessageHash, signature);
        if (!validSigners[recovered]) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        return ("", _packValidationData(false, validUntil, validAfter));
    }

    function postOp(
        PostOpMode, // mode
        bytes calldata, // context
        uint256, // actualGasCost
        uint256 // actualUserOpFeePerGas
    )
        external
        view
        onlyEntryPoint
    { }

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        validUntil = uint48(bytes6(paymasterAndData[VALID_UNTIL_OFFSET:VALID_AFTER_OFFSET]));
        validAfter = uint48(bytes6(paymasterAndData[VALID_AFTER_OFFSET:SIGNATURE_OFFSET]));
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(
        PackedUserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter
    )
        public
        view
        returns (bytes32)
    {
        //can't use userOp.hash, since it contains also the paymasterAndData itself.
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * Add a deposit for this paymaster, used for paying for transaction fees.
     */
    function deposit() public payable {
        entryPoint.depositTo{ value: msg.value }(address(this));
    }

    /**
     * Withdraw value from the deposit.
     * @param withdrawAddress - Target to send to.
     * @param amount          - Amount to withdraw.
     */
    function withdrawTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /**
     * Add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
    }

    /**
     * Return current paymaster's deposit on the entryPoint.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * Withdraw the entire paymaster's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    function setSigner(address signer, bool isValid) external onlyOwner {
        if (validSigners[signer] == isValid) revert SignerIsAlreadySet(signer, isValid);
        validSigners[signer] = isValid;
        emit SignerSet(signer, isValid);
    }

    /**
     * Helper to get the balance of an ERC20 token or native asset
     * @param token - The address of the token (using a special default for native)
     * @param account - The address of the account that will be queried
     */
    function _balance(address token, address account) internal view returns (uint256 balance) {
        balance = token == _NATIVE_ASSET ? account.balance : IERC20(token).balanceOf(account);
    }

    /**
     * Helper to pack the return value for validateUserOp, when not using an aggregator.
     * @param sigFailed  - True for signature failure, false for success.
     * @param validUntil - Last timestamp this UserOperation is valid (or zero for infinite).
     * @param validAfter - First timestamp this UserOperation is valid.
     */
    function _packValidationData(
        bool sigFailed,
        uint48 validUntil,
        uint48 validAfter
    )
        internal
        pure
        returns (uint256)
    {
        return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << (160 + 48));
    }

    /**
     * Helper to pack the postOp data
     */
    function _packPostOpData(
        address feeReceiver,
        address token,
        uint256 amount,
        uint256 balance
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(feeReceiver, token, amount, balance);
    }
}

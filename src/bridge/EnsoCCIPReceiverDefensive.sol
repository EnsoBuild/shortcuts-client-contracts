// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { IEnsoCCIPReceiverDefensive } from "../interfaces/IEnsoCCIPReceiverDefensive.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

/// @title EnsoCCIPReceiverDefensive
/// @author Enso
/// @notice Destination-side CCIP receiver that validates source chain/sender, enforces replay
///         protection, and forwards a single bridged ERC-20 to Enso Shortcuts via the Enso Router.
/// @dev The contract:
///      - Relies on Chainlink CCIP’s router gating via {CCIPReceiver}.
///      - Adds allowlists for source chain selectors and source senders (per chain).
///      - Guards against duplicate delivery with a messageId map.
///      - Expects exactly one ERC-20 in `destTokenAmounts`; amount must be non-zero.
///      - Executes Shortcuts through a self-call pattern (`try this.execute(...)`) so we can
///        catch and handle reverts and sweep funds to a fallback receiver in the payload.
contract EnsoCCIPReceiverDefensive is IEnsoCCIPReceiverDefensive, CCIPReceiver, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    uint256 private constant VERSION = 1;

    /// @dev Immutable Enso Router used to dispatch tokens + call Shortcuts.
    /// forge-lint: disable-next-item(screaming-snake-case-immutable)
    IEnsoRouter private immutable i_ensoRouter;

    /// @dev Allowlist by source chain selector.
    /// forge-lint: disable-next-item(mixed-case-variable)
    mapping(uint64 sourceChainSelector => bool isAllowed) private s_allowedSourceChain;

    /// @dev Per-(chain selector, sender) allowlist.
    ///      Key is computed as: keccak256(abi.encode(sourceChainSelector, sender)),
    ///      where `sender` is the EVM address decoded from `Any2EVMMessage.sender` bytes.
    /// forge-lint: disable-next-item(mixed-case-variable)
    mapping(bytes32 key => bool isAllowed) private s_allowedSender;

    mapping(bytes32 messageId => bool isEscrow) private s_escrowMessage;

    /// @dev Replay protection: tracks CCIP message IDs that were executed successfully (or handled).
    /// forge-lint: disable-next-item(mixed-case-variable)
    mapping(bytes32 messageId => bool wasExecuted) private s_executedMessage;

    /// @notice Initializes the receiver with the CCIP router and Enso Router.
    /// @dev The owner is set via {Ownable} base (passed in to support 2-step ownership if desired).
    /// @param _owner Address to set as initial owner.
    /// @param _ccipRouter Address of the CCIP Router on the destination chain.
    /// @param _ensoRouter Address of the Enso Router that will execute Shortcuts.
    constructor(address _owner, address _ccipRouter, address _ensoRouter) Ownable(_owner) CCIPReceiver(_ccipRouter) {
        i_ensoRouter = IEnsoRouter(_ensoRouter);
    }

    /// @notice CCIP router callback: validates message, enforces replay protection, and dispatches.
    /// @dev Flow:
    ///      1) Check duplicate by messageId (fail fast).
    ///      2) Check allowlisted source chain and sender (decoded from `message.sender`).
    ///      3) Enforce exactly one ERC-20 delivered (and non-zero amount).
    ///      4) Decode payload `(receiver, estimatedGas, shortcutData)`.
    ///      5) Optional gas self-check (if `estimatedGas` > 0).
    ///      6) Mark executed, attempt `execute(...)` via self-call; on failure, sweep token to `receiver`.
    /// @param _message The CCIP Any2EVM message with metadata, payload, and delivered tokens.
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        (
            address token,
            uint256 amount,
            address receiver,
            bytes memory shortcutData,
            ErrorCode errorCode,
            bytes memory errorData
        ) = _validateMessage(_message);

        if (errorCode != ErrorCode.NO_ERROR) {
            emit IEnsoCCIPReceiverDefensive.MessageValidationFailed(_message.messageId, errorCode, errorData);

            RefundKind refundKind = _getRefundPolicy(errorCode);
            if (refundKind == RefundKind.NONE) {
                // NOTE: ErrorCode.ALREADY_EXECUTED → no-op;
                return;
            }
            if (refundKind == RefundKind.TO_RECEIVER) {
                s_executedMessage[_message.messageId] = true;
                IERC20(token).safeTransfer(receiver, amount);
                return;
            }
            if (refundKind == RefundKind.TO_ESCROW) {
                s_executedMessage[_message.messageId] = true;
                emit MessageQuarantined(_message.messageId, errorCode, token, amount, receiver);
                s_escrowMessage[_message.messageId] = true;
            }

            // NOTE: make sure this is caught in development
            revert EnsoCCIPReceiver_UnsupportedRefundKind(refundKind);
        }

        s_executedMessage[_message.messageId] = true;

        // Attempt Shortcuts execution; on failure, sweep funds to the fallback receiver.
        try this.execute(token, amount, shortcutData) {
            emit IEnsoCCIPReceiverDefensive.ShortcutExecutionSuccessful(_message.messageId);
        } catch (bytes memory err) {
            emit IEnsoCCIPReceiverDefensive.ShortcutExecutionFailed(_message.messageId, err);
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    function decodeMessageData(bytes calldata _data) external view returns (address, uint256, bytes memory) {
        if (msg.sender != address(this)) {
            revert IEnsoCCIPReceiverDefensive.EnsoCCIPReceiver_OnlySelf();
        }

        return abi.decode(_data, (address, uint256, bytes));
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function execute(address _token, uint256 _amount, bytes calldata _shortcutData) external {
        if (msg.sender != address(this)) {
            revert IEnsoCCIPReceiverDefensive.EnsoCCIPReceiver_OnlySelf();
        }
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(_token, _amount) });
        IERC20(_token).forceApprove(address(i_ensoRouter), _amount);

        i_ensoRouter.routeSingle(tokenIn, _shortcutData);
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function setAllowedSender(uint64 _sourceChainSelector, address _sender, bool _isAllowed) external onlyOwner {
        s_allowedSender[_getAllowedSenderKey(_sourceChainSelector, _sender)] = _isAllowed;
        emit IEnsoCCIPReceiverDefensive.AllowedSenderSet(_sourceChainSelector, _sender, _isAllowed);
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function setAllowedSourceChain(uint64 _sourceChainSelector, bool _isAllowed) external onlyOwner {
        s_allowedSourceChain[_sourceChainSelector] = _isAllowed;
        emit IEnsoCCIPReceiverDefensive.AllowedSourceChainSet(_sourceChainSelector, _isAllowed);
    }

    /// @dev currently only for malformed messages, as multiple tokens are not supported by CCIP
    function sweepMessageInEscrow(
        bytes32 _messageId,
        address _token,
        uint256 _amount,
        address _to
    )
        external
        onlyOwner
    {
        if (!s_escrowMessage[_messageId]) {
            revert EnsoCCIPReceiver_MissingEscrow(_messageId);
        }
        delete s_escrowMessage[_messageId];

        IERC20(_token).safeTransfer(_to, _amount);
        emit EscrowSwept(_messageId, _token, _amount, _to);
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function getEnsoRouter() external view returns (address) {
        return address(i_ensoRouter);
    }

    function isMessageInEscrow(bytes32 _messageId) external view returns (bool) {
        return s_escrowMessage[_messageId];
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function isSenderAllowed(uint64 _sourceChainSelector, address _sender) external view returns (bool) {
        return s_allowedSender[_getAllowedSenderKey(_sourceChainSelector, _sender)];
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function isSourceChainAllowed(uint64 _sourceChainSelector) external view returns (bool) {
        return s_allowedSourceChain[_sourceChainSelector];
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function version() external pure returns (uint256) {
        return VERSION;
    }

    /// @inheritdoc IEnsoCCIPReceiverDefensive
    function wasMessageExecuted(bytes32 _messageId) external view returns (bool) {
        return s_executedMessage[_messageId];
    }

    function _getRefundPolicy(ErrorCode _errorCode) private pure returns (RefundKind) {
        if (_errorCode == ErrorCode.NO_ERROR || _errorCode == ErrorCode.ALREADY_EXECUTED) {
            return RefundKind.NONE;
        }
        if (
            _errorCode == ErrorCode.PAUSED || _errorCode == ErrorCode.SOURCE_CHAIN_NOT_ALLOWED
                || _errorCode == ErrorCode.SENDER_NOT_ALLOWED || _errorCode == ErrorCode.INSUFFICIENT_GAS
        ) {
            return RefundKind.TO_RECEIVER;
        }
        if (
            _errorCode == ErrorCode.MALFORMED_MESSAGE_DATA || _errorCode == ErrorCode.NO_TOKENS
                || _errorCode == ErrorCode.NO_TOKEN_AMOUNT || _errorCode == ErrorCode.TOO_MANY_TOKENS
        ) {
            return RefundKind.TO_ESCROW;
        }

        // NOTE: make sure this is caught in development
        revert IEnsoCCIPReceiverDefensive.EnsoCCIPReceiver_UnsupportedErrorCode(_errorCode);
    }

    function _validateMessage(Client.Any2EVMMessage memory _message)
        private
        view
        returns (
            address token,
            uint256 amount,
            address receiver,
            bytes memory shortcutData,
            ErrorCode errorCode,
            bytes memory errorData
        )
    {
        bytes32 messageId = _message.messageId;
        if (s_executedMessage[messageId]) {
            errorData = abi.encode(messageId);
            return (token, amount, receiver, shortcutData, ErrorCode.ALREADY_EXECUTED, errorData);
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = _message.destTokenAmounts;
        if (destTokenAmounts.length == 0) {
            return (token, amount, receiver, shortcutData, ErrorCode.NO_TOKENS, errorData);
        }

        if (destTokenAmounts.length > 1) {
            return (token, amount, receiver, shortcutData, ErrorCode.TOO_MANY_TOKENS, errorData);
        }

        token = destTokenAmounts[0].token;
        amount = destTokenAmounts[0].amount;

        if (amount == 0) {
            return (token, amount, receiver, shortcutData, ErrorCode.NO_TOKEN_AMOUNT, errorData);
        }

        uint256 estimatedGas;
        // TODO: find an assembly alternative...
        try this.decodeMessageData(_message.data) returns (
            address decodedReceiver, uint256 decodedEstimatedGas, bytes memory decodedShortcutData
        ) {
            receiver = decodedReceiver;
            estimatedGas = decodedEstimatedGas;
            shortcutData = decodedShortcutData;
        } catch {
            return (token, amount, receiver, shortcutData, ErrorCode.MALFORMED_MESSAGE_DATA, errorData);
        }

        if (paused()) {
            return (token, amount, receiver, shortcutData, ErrorCode.PAUSED, errorData);
        }

        uint64 sourceChainSelector = _message.sourceChainSelector;
        if (!s_allowedSourceChain[sourceChainSelector]) {
            errorData = abi.encode(sourceChainSelector);
            return (token, amount, receiver, shortcutData, ErrorCode.SOURCE_CHAIN_NOT_ALLOWED, errorData);
        }

        address sender = abi.decode(_message.sender, (address));
        if (!s_allowedSender[_getAllowedSenderKey(sourceChainSelector, sender)]) {
            errorData = abi.encode(sourceChainSelector, sender);
            return (token, amount, receiver, shortcutData, ErrorCode.SENDER_NOT_ALLOWED, errorData);
        }

        uint256 availableGas = gasleft();
        if (estimatedGas != 0 && availableGas < estimatedGas) {
            errorData = abi.encode(availableGas, estimatedGas);
            return (token, amount, receiver, shortcutData, ErrorCode.INSUFFICIENT_GAS, errorData);
        }

        return (token, amount, receiver, shortcutData, ErrorCode.NO_ERROR, errorData);
    }

    /// @dev Computes the composite allowlist key for (chainSelector, sender).
    ///      ABI-equivalent to:
    ///          keccak256(abi.encode(chainSelector, sender))
    ///      and implemented in Yul to avoid an extra temporary allocation.
    ///      Semantics are identical to the high-level version.
    ///
    ///      Canonicality (no masking required):
    ///      - `sender` is a canonical Solidity `address`, either decoded via
    ///        `abi.decode(...,(address))` from `Any2EVMMessage.sender` or received
    ///        as a public/external ABI parameter. In both cases the VM zero-extends
    ///        it to a full 32-byte word when written to memory.
    ///      - `chainSelector` is a `uint64` and is zero-extended to 32 bytes by the ABI/VM.
    ///
    /// @param _chainSelector The CCIP source chain selector (uint64).
    /// @param _sender        The source application address decoded from `Any2EVMMessage.sender`.
    /// @return allowKey      keccak256(abi.encode(_chainSelector, _sender)).
    function _getAllowedSenderKey(uint64 _chainSelector, address _sender) private pure returns (bytes32 allowKey) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, _chainSelector)
            mstore(add(ptr, 0x20), _sender)
            allowKey := keccak256(ptr, 0x40)
        }
    }
}

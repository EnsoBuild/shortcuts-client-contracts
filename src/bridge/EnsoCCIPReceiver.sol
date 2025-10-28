// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { IEnsoCCIPReceiver } from "../interfaces/IEnsoCCIPReceiver.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { CCIPReceiver, Client } from "chainlink-ccip/applications/CCIPReceiver.sol";
import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EnsoCCIPReceiver
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
contract EnsoCCIPReceiver is Ownable2Step, CCIPReceiver, IEnsoCCIPReceiver {
    using SafeERC20 for IERC20;

    /// @dev Immutable Enso Router used to dispatch tokens + call Shortcuts.
    IEnsoRouter private immutable i_ensoRouter;

    /// @dev Allowlist by source chain selector.
    mapping(uint64 sourceChainSelector => bool isAllowed) private s_allowedSourceChain;
    /// @dev Allowlist of source senders per chain selector.
    mapping(uint64 sourceChainSelector => mapping(address sender => bool isAllowed)) private s_allowedSender;
    /// @dev Replay protection: tracks CCIP message IDs that were executed successfully (or handled).
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
        bytes32 messageId = _message.messageId;
        if (s_executedMessage[messageId]) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_AlreadyExecuted(messageId);
        }

        uint64 sourceChainSelector = _message.sourceChainSelector;
        if (!s_allowedSourceChain[sourceChainSelector]) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_SourceChainNotAllowed(sourceChainSelector);
        }

        address sender = abi.decode(_message.sender, (address));
        if (!s_allowedSender[sourceChainSelector][sender]) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_SenderNotAllowed(sourceChainSelector, sender);
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = _message.destTokenAmounts;
        if (destTokenAmounts.length == 0) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_NoTokens();
        }

        if (destTokenAmounts.length > 1) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_TooManyTokens();
        }

        address token = destTokenAmounts[0].token;
        uint256 amount = destTokenAmounts[0].amount;

        if (amount == 0) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_NoTokenAmount(token);
        }

        (address receiver, uint256 estimatedGas, bytes memory shortcutData) =
            abi.decode(_message.data, (address, uint256, bytes));

        uint256 availableGas = gasleft();
        if (estimatedGas != 0 && availableGas < estimatedGas) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_InsufficientGas(availableGas, estimatedGas);
        }

        s_executedMessage[messageId] = true;

        // Attempt Shortcuts execution; on failure, sweep funds to the fallback receiver.
        try this.execute(token, amount, shortcutData) {
            emit IEnsoCCIPReceiver.ShortcutExecutionSuccessful(messageId);
        } catch (bytes memory err) {
            emit IEnsoCCIPReceiver.ShortcutExecutionFailed(messageId, err);
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function execute(address _token, uint256 _amount, bytes calldata _shortcutData) external {
        if (msg.sender != address(this)) {
            revert IEnsoCCIPReceiver.EnsoCCIPReceiver_OnlySelf();
        }
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(_token, _amount) });
        IERC20(_token).forceApprove(address(i_ensoRouter), _amount);

        i_ensoRouter.routeSingle(tokenIn, _shortcutData);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function setAllowedSender(uint64 _sourceChainSelector, address _sender, bool _isAllowed) external onlyOwner {
        s_allowedSender[_sourceChainSelector][_sender] = _isAllowed;
        emit IEnsoCCIPReceiver.AllowedSenderSet(_sourceChainSelector, _sender, _isAllowed);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function setAllowedSourceChain(uint64 _sourceChainSelector, bool _isAllowed) external onlyOwner {
        s_allowedSourceChain[_sourceChainSelector] = _isAllowed;
        emit IEnsoCCIPReceiver.AllowedSourceChainSet(_sourceChainSelector, _isAllowed);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function getEnsoRouter() external view returns (address) {
        return address(i_ensoRouter);
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function isSenderAllowed(uint64 _sourceChainSelector, address _sender) external view returns (bool) {
        return s_allowedSender[_sourceChainSelector][_sender];
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function isSourceChainAllowed(uint64 _sourceChainSelector) external view returns (bool) {
        return s_allowedSourceChain[_sourceChainSelector];
    }

    /// @inheritdoc IEnsoCCIPReceiver
    function wasMessageExecuted(bytes32 _messageId) external view returns (bool) {
        return s_executedMessage[_messageId];
    }
}

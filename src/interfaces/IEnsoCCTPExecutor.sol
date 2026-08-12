// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IMessageTransmitterV2 } from "../vendor/cctp/interfaces/IMessageTransmitterV2.sol";
import { ITokenMessengerV2 } from "../vendor/cctp/interfaces/ITokenMessengerV2.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IEnsoCCTPExecutor {
    struct CctpCallback {
        bytes4 magic;
        uint8 version;
        bytes32 requestId;
        address refundReceiver;
        uint256 executionFee;
        bytes callbackData;
    }

    event ShortcutExecutionSuccessful(
        bytes32 indexed requestId, address indexed submitter, uint256 mintAmount, uint256 executionFee
    );
    event ShortcutExecutionFailed(
        bytes32 indexed requestId,
        address indexed submitter,
        address refundReceiver,
        uint256 refundAmount,
        uint256 executionFee
    );
    event CctpMessageRecovered(address indexed receiver, uint256 mintAmount);

    error ExecutionFeeExceedsMintAmount(uint256 executionFee, uint256 mintAmount);
    error InvalidCallback();
    error InvalidDestinationCaller(address caller);
    error InvalidMessageRecipient(address recipient);
    error InvalidMintRecipient(address recipient);
    error InvalidMintToken(address token);
    error InvalidRecoveryReceiver(address receiver);
    error InvalidRefundReceiver(address receiver);
    error MessageTransmitterReturnedFalse();
    error NoTokensMinted();
    error NotSelf();
    error RouterCallFailed();
    error UnsupportedBurnMessageVersion(uint32 version);
    error UnsupportedMessageVersion(uint32 version);
    error ZeroAddress();

    function HOOK_MAGIC() external view returns (bytes4);

    function HOOK_VERSION() external view returns (uint8);

    function MESSAGE_TRANSMITTER() external view returns (IMessageTransmitterV2);

    function TOKEN_MESSENGER() external view returns (ITokenMessengerV2);

    function USDC() external view returns (IERC20);

    function ROUTER() external view returns (address);

    function SHORTCUTS() external view returns (address);

    function SUPPORTED_MESSAGE_VERSION() external view returns (uint32);

    function SUPPORTED_BURN_MESSAGE_VERSION() external view returns (uint32);

    function execute(bytes calldata message, bytes calldata attestation) external;

    function executeCallback(uint256 callbackAmount, bytes calldata callbackData) external;

    function executeWithoutCallback(bytes calldata message, bytes calldata attestation, address receiver) external;

    function recoverTokens(address token, address receiver, uint256 amount) external;

    function pause() external;

    function unpause() external;
}

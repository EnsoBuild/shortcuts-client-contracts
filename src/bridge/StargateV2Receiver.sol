// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

import { VM } from "enso-weiroll/VM.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract StargateV2Receiver is VM, ILayerZeroComposer {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable endpoint;

    event ShortcutExecutionSuccessful(bytes32 guid, bytes32 requestId);
    event ShortcutExecutionFailed(bytes32 guid, bytes32 requestId);

    error NotEndpoint(address sender);
    error NotSelf();
    error TransferFailed(bytes32 guid, address receiver);

    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    function lzCompose(address, bytes32 _guid, bytes calldata _message, address, bytes calldata) external payable {
        if (msg.sender != endpoint) revert NotEndpoint(msg.sender);

        bytes memory composeMsg = _message.composeMsg();
        (address token, address receiver, bytes32 requestId, bytes32[] memory commands, bytes[] memory state) =
            abi.decode(composeMsg, (address, address, bytes32, bytes32[], bytes[]));

        // try to execute shortcut
        try this.execute(commands, state) {
            emit ShortcutExecutionSuccessful(_guid, requestId);
        } catch {
            // if shortcut fails send funds to receiver
            emit ShortcutExecutionFailed(_guid, requestId);
            uint256 amount = _message.amountLD();
            if (token == _NATIVE_ASSET) {
                (bool success,) = receiver.call{ value: amount }("");
                if (!success) revert TransferFailed(_guid, receiver);
            } else {
                IERC20(token).safeTransfer(receiver, amount);
            }
        }
    }

    function execute(bytes32[] calldata commands, bytes[] memory state) public {
        if (msg.sender != address(this)) revert NotSelf();
        _execute(commands, state);
    }

    receive() external payable { }
}

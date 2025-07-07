// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IPool } from "./interfaces/stargate/IPool.sol";
import { ITokenMessaging } from "./interfaces/stargate/ITokenMessaging.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract StargateV2Receiver is Ownable, ILayerZeroComposer {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = address(0);

    address public immutable endpoint;
    ITokenMessaging public immutable tokenMessaging;
    IEnsoRouter public immutable router;

    uint256 public immutable reserveGas;

    event ShortcutExecutionSuccessful(bytes32 guid);
    event ShortcutExecutionFailed(bytes32 guid, bytes error);
    event InsufficientGas(bytes32 guid);

    error NotEndpoint(address sender);
    error NotSelf();
    error TransferFailed(address receiver);
    error InvalidAsset(address oft);

    constructor(
        address _endpoint,
        address _tokenMessaging,
        address _router,
        address _owner,
        uint256 _reserveGas
    )
        Ownable(_owner)
    {
        endpoint = _endpoint;
        tokenMessaging = ITokenMessaging(_tokenMessaging);
        router = IEnsoRouter(_router);
        reserveGas = _reserveGas;
    }

    // layer zero callback
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address, // _executor, we don't restrict who can execute composed messages to this contract
        bytes calldata // _extraData, we don't use any extra data from the executor
    )
        external
        payable
    {
        if (msg.sender != endpoint) revert NotEndpoint(msg.sender);
        // confirm that the _from address is a valid stargate oft
        if (tokenMessaging.assetIds(_from) == 0) revert InvalidAsset(_from);

        address token = IPool(_from).token();

        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();
        (address receiver, bytes memory shortcutData) = abi.decode(composeMsg, (address, bytes));

        uint256 availableGas = gasleft();
        if (availableGas < reserveGas) {
            emit InsufficientGas(_guid);
            _transfer(token, receiver, amount);
        } else {
            // try to execute shortcut
            try this.execute{ gas: availableGas - reserveGas }(token, amount, shortcutData, msg.value) {
                emit ShortcutExecutionSuccessful(_guid);
            } catch (bytes memory err) {
                // if shortcut fails send funds to receiver
                emit ShortcutExecutionFailed(_guid, err);
                _transfer(token, receiver, amount);
                if (msg.value > 0) {
                    _transfer(_NATIVE_ASSET, receiver, msg.value);
                }
            }
        }
    }

    // execute shortcut using router
    function execute(address token, uint256 amount, bytes calldata data, uint256 value) public {
        if (msg.sender != address(this)) revert NotSelf();
        Token memory tokenIn;
        if (token == _NATIVE_ASSET) {
            value += amount;
            // support backwards compatibility by including amount data
            tokenIn = Token(TokenType.Native, abi.encode(value)); 
        } else {
            tokenIn = Token(TokenType.ERC20, abi.encode(token, amount));
            IERC20(token).forceApprove(address(router), amount);
        }
        if (value > 0 && token != _NATIVE_ASSET) {
            Token[] memory tokensIn = new Token[](2);
            tokensIn[0] = tokenIn;
            // support backwards compatibility by including amount data
            tokensIn[1] = Token(TokenType.Native, abi.encode(value));
            router.routeMulti{ value: value }(tokensIn, data);
        } else {
            router.routeSingle{ value: value }(tokenIn, data);
        }
    }

    // sweep funds to the contract owner in order to refund user
    function sweep(address[] memory tokens) external onlyOwner {
        address receiver = owner();
        address token;
        for (uint256 i = 0; i < tokens.length; ++i) {
            token = tokens[i];
            _transfer(token, receiver, _balance(token));
        }
    }

    function _transfer(address token, address receiver, uint256 amount) internal {
        if (token == _NATIVE_ASSET) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) revert TransferFailed(receiver);
        } else {
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    function _balance(address token) internal view returns (uint256 balance) {
        balance = token == _NATIVE_ASSET ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    receive() external payable {
        // receive all native transfers
    }
}

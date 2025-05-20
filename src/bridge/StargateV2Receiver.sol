// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface IRouter {
    enum TokenType {
        Native,
        ERC20,
        ERC721,
        ERC1155
    }

    struct Token {
        TokenType tokenType;
        bytes data;
    }

    function routeSingle(
        Token calldata tokenIn,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory response);
}

interface ITokenMessaging {
    function assetIds(address) external view returns (uint16);
}

interface IPool {
    function token() external view returns (address);
}

contract StargateV2Receiver is Ownable, ILayerZeroComposer {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = address(0);

    address public immutable endpoint;
    ITokenMessaging public immutable tokenMessaging;
    IRouter public immutable router;

    uint256 public immutable reserveGas;

    event ShortcutExecutionSuccessful(bytes32 guid);
    event ShortcutExecutionFailed(bytes32 guid);
    event InsufficientGas(bytes32 guid);

    error NotEndpoint(address sender);
    error NotSelf();
    error TransferFailed(address receiver);
    error InvalidAsset();

    constructor(address _endpoint, address _tokenMessaging, address _router, address _owner, uint256 _reserveGas) Ownable(_owner) {
        endpoint = _endpoint;
        tokenMessaging = ITokenMessaging(_tokenMessaging);
        router = IRouter(_router);
        reserveGas = _reserveGas;
    }

    // layer zero callback
    function lzCompose(address _from, bytes32 _guid, bytes calldata _message, address, bytes calldata) external payable {
        if (msg.sender != endpoint) revert NotEndpoint(msg.sender);
        if (tokenMessaging.assetIds(_from) == 0) revert InvalidAsset();

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
            try this.execute{ gas: availableGas - reserveGas }(token, amount, shortcutData) {
                emit ShortcutExecutionSuccessful(_guid);
            } catch {
                // if shortcut fails send funds to receiver
                emit ShortcutExecutionFailed(_guid);
                _transfer(token, receiver, amount);
            }
        }
        
    }

    // execute shortcut using router
    function execute(address token, uint256 amount, bytes calldata data) public {
        if (msg.sender != address(this)) revert NotSelf();
        IRouter.Token memory tokenIn;
        uint256 value;
        if (token == _NATIVE_ASSET) {
            tokenIn = IRouter.Token(IRouter.TokenType.Native, abi.encode(amount));
            value = amount;
        } else {
            tokenIn = IRouter.Token(IRouter.TokenType.ERC20, abi.encode(token, amount));
            IERC20(token).forceApprove(address(router), amount);
        }
        router.routeSingle{ value: value }(tokenIn, data);
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

    receive() external payable { }
}

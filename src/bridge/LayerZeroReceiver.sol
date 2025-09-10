// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IPool } from "./interfaces/layerzero/IPool.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract LayerZeroReceiver is Ownable, ILayerZeroComposer {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = address(0);

    address public immutable endpoint;
    IEnsoRouter public immutable router;

    mapping(address => bool) public validOFT;
    mapping(address => bool) public validRegistrar;
    mapping(bytes32 => bool) public messageExecuted;

    event ShortcutExecutionSuccessful(bytes32 guid);
    event ShortcutExecutionFailed(bytes32 guid, bytes error);
    event OFTAdded(address oft);
    event OFTRemoved(address oft);
    event RegistrarAdded(address account);
    event RegistrarRemoved(address account);
    event FundsCollected(address token, uint256 amount);

    error InsufficientGas(bytes32 guid, uint256 estimatedGas, uint256 availableGas);
    error NotEndpoint(address sender);
    error NotRegistrar(address sender);
    error NotSelf();
    error TransferFailed(address receiver);
    error InvalidOFT(address oft);
    error EndpointNotSet();
    error RouterNotSet();
    error InvalidMsgValue(uint256 actual, uint256 expected);
    error MessageExecuted(bytes32 key);

    constructor(address _endpoint, address _router, address _owner) Ownable(_owner) {
        if (_endpoint == address(0)) revert EndpointNotSet();
        if (_router == address(0)) revert RouterNotSet();
        endpoint = _endpoint;
        router = IEnsoRouter(_router);
        validRegistrar[_owner] = true;
        emit RegistrarAdded(_owner);
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
        if (!validOFT[_from]) revert InvalidOFT(_from);
        bytes32 key = getMessageKey(_from, _guid, _message);
        if (messageExecuted[key]) revert MessageExecuted(key);

        address token = IPool(_from).token();

        uint256 amount = _message.amountLD();
        bytes memory composeMsg = _message.composeMsg();
        (address receiver, uint256 nativeDrop, uint256 estimatedGas, bytes memory shortcutData) =
            abi.decode(composeMsg, (address, uint256, uint256, bytes));
        if (msg.value < nativeDrop) revert InvalidMsgValue(msg.value, nativeDrop);
        uint256 availableGas = gasleft();
        if (availableGas < estimatedGas) revert InsufficientGas(_guid, estimatedGas, availableGas);

        // try to execute shortcut
        try this.execute(token, amount, shortcutData, msg.value) {
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

    // execute shortcut using router
    function execute(address token, uint256 amount, bytes calldata data, uint256 value) external {
        if (msg.sender != address(this)) revert NotSelf();
        Token memory tokenIn;
        if (token == _NATIVE_ASSET) {
            // calls shouldn't be built so that they do both an lzReceive deposit of the native token
            // and a native drop, but just in case, we add both amounts for our call to the router
            value += amount;
            // support older versions of the router by including amount data for native token
            tokenIn = Token(TokenType.Native, abi.encode(value));
        } else {
            tokenIn = Token(TokenType.ERC20, abi.encode(token, amount));
            IERC20(token).forceApprove(address(router), amount);
        }
        if (value > 0 && token != _NATIVE_ASSET) {
            // since this call will use token + native asset, setup a routeMulti call
            Token[] memory tokensIn = new Token[](2);
            tokensIn[0] = tokenIn;
            // support older versions of the router by including amount data for native token
            tokensIn[1] = Token(TokenType.Native, abi.encode(value));
            router.routeMulti{ value: value }(tokensIn, data);
        } else {
            // setup a routeSingle call
            router.routeSingle{ value: value }(tokenIn, data);
        }
    }

    function setOFTs(address[] calldata ofts) external {
        if (!validRegistrar[msg.sender]) revert NotRegistrar(msg.sender);
        for (uint256 i = 0; i < ofts.length; ++i) {
            validOFT[ofts[i]] = true;
            emit OFTAdded(ofts[i]);
        }
    }

    function removeOFTs(address[] calldata ofts) external {
        if (!validRegistrar[msg.sender]) revert NotRegistrar(msg.sender);
        for (uint256 i = 0; i < ofts.length; ++i) {
            delete validOFT[ofts[i]];
            emit OFTRemoved(ofts[i]);
        }
    }

    function setRegistrar(address account) external onlyOwner {
        validRegistrar[account] = true;
        emit RegistrarAdded(account);
    }

    function removeRegistrar(address account) external onlyOwner {
        delete validRegistrar[account];
        emit RegistrarRemoved(account);
    }

    // sweep funds to the contract owner in order to refund user
    function sweep(bytes32 messageKey, address token, uint256 amount) external onlyOwner {
        // message key is passed to block subsequent calls to lzCompose in case a failing message becomes executable.
        // internal message data is not validated in case the message itself is malformed or incorrect
        // (e.g. oft returns incorrect token)
        messageExecuted[messageKey] = true;

        _transfer(token, owner(), amount);
        emit FundsCollected(token, amount);
    }

    function getMessageKey(address from, bytes32 guid, bytes calldata message) public pure returns (bytes32) {
        return keccak256(abi.encode(from, guid, message));
    }

    function _transfer(address token, address receiver, uint256 amount) internal {
        if (token == _NATIVE_ASSET) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) revert TransferFailed(receiver);
        } else {
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    receive() external payable {
        // receive all native transfers
    }
}

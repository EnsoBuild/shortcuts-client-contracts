// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

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

contract StargateV2Receiver is ILayerZeroComposer {
    using OFTComposeMsgCodec for bytes;
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = address(0);

    address public immutable endpoint;
    ITokenMessaging public immutable tokenMessaging;
    IRouter public immutable router;

    uint256 public immutable transferGas;
    uint256 public immutable reserveGas;

    mapping(address => mapping(address => uint256)) public unreceived;

    event ShortcutExecutionSuccessful(bytes32 guid);
    event ShortcutExecutionFailed(bytes32 guid);
    event InsufficientGas(bytes32 guid);
    event TransferSuccessful(address receiver);
    event FundsToClaim(address receiver, address token, uint256 amount);

    error NotEndpoint(address sender);
    error NotSelf();
    error TransferFailed(address receiver);
    error InvalidAsset();

    constructor(address _endpoint, address _tokenMessaging, address _router, uint256 _transferGas, uint256 _reserveGas) {
        endpoint = _endpoint;
        tokenMessaging = ITokenMessaging(_tokenMessaging);
        router = IRouter(_router);
        transferGas = _transferGas;
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
        uint256 fallbackGas = transferGas + reserveGas;
        if (availableGas < fallbackGas) {
            emit InsufficientGas(_guid);
            _tryTransfer(token, receiver, amount);
        } else {
            // try to execute shortcut
            try this.execute{ gas: availableGas - fallbackGas }(token, amount, shortcutData) {
                emit ShortcutExecutionSuccessful(_guid);
            } catch {
                // if shortcut fails send funds to receiver
                emit ShortcutExecutionFailed(_guid);
                _tryTransfer(token, receiver, amount);
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

    // claim funds that are held on this contract
    function claim(address token, address receiver) external {
        uint256 amount = unreceived[token][receiver];
        delete unreceived[token][receiver];
        bool success = _transfer(token, receiver, amount, gasleft());
        if (!success) revert TransferFailed(receiver);
    }

    function _tryTransfer(address token, address receiver, uint256 amount) internal {
        uint256 availableGas = gasleft();
        if (availableGas < reserveGas) {
            // try to set amount in state so it can be retrieved manually
            unreceived[token][receiver] += amount;
            emit FundsToClaim(receiver, token, amount);
        } else {
            bool success = _transfer(token, receiver, amount, availableGas - reserveGas);
            if (!success) {
                // set amount in state so it can be retrieved manually
                unreceived[token][receiver] += amount;
                emit FundsToClaim(receiver, token, amount);
            } else {
                emit TransferSuccessful(receiver);
            }
        }
    }

    function _transfer(address token, address receiver, uint256 amount, uint256 gas) internal returns (bool success) {
        if (token == _NATIVE_ASSET) {
            (success,) = receiver.call{ gas: gas, value: amount }("");
        } else {
            success = _tryERC20SafeTransfer(token, receiver, amount, gas);
        }
    }

    function _tryERC20SafeTransfer(address token, address receiver, uint256 amount, uint256 gas) internal returns (bool success) {
        success = _callOptionalReturnBool(token, abi.encodeCall(IERC20.transfer, (receiver, amount)), gas);
    }

    // taken from OpenZeppelin's SafeERC20 and modified to control the gas sent
    function _callOptionalReturnBool(address token, bytes memory data, uint256 txGas) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(txGas, token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? token.code.length > 0 : returnValue == 1);
    }

    receive() external payable { }
}

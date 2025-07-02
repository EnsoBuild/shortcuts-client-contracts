// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoShortcuts } from "../EnsoShortcuts.sol";

import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";

contract EnsoRouter is IEnsoRouter {
    using SafeERC20 for IERC20;

    address public immutable shortcuts;

    error WrongMsgValue(uint256 value, uint256 expectedAmount);
    error AmountTooLow(Token token, uint256 amount, uint256 minAmount);
    error DuplicateNativeAsset();
    error UnsupportedTokenType(TokenType tokenType);

    constructor() {
        shortcuts = address(new EnsoShortcuts(address(this)));
    }

    /// @notice Route a single token via a call to the shortcuts contract
    /// @param tokenIn The encoded data for the token to send
    /// @param data The call data to be sent to the shortcuts contract
    function routeSingle(Token calldata tokenIn, bytes calldata data) public payable returns (bytes memory response) {
        bool isNativeAsset = _transfer(tokenIn);
        if (!isNativeAsset && msg.value != 0) revert WrongMsgValue(msg.value, 0);
        response = _execute(data);
    }

    /// @notice Route multiple tokens via a call to the shortcuts contract
    /// @param tokensIn The encoded data for the tokens to send
    /// @param data The call data to be sent to the shortcuts contract
    function routeMulti(
        Token[] calldata tokensIn,
        bytes calldata data
    )
        public
        payable
        returns (bytes memory response)
    {
        bool isNativeAsset;
        for (uint256 i; i < tokensIn.length; ++i) {
            if (_transfer(tokensIn[i])) {
                if (isNativeAsset) revert DuplicateNativeAsset(); // Native asset can only be included once
                isNativeAsset = true;
            }
        }
        if (!isNativeAsset && msg.value != 0) revert WrongMsgValue(msg.value, 0);

        response = _execute(data);
    }

    /// @notice Route a single token via a call to the shortcuts contract and revert if there is insufficient token
    /// received
    /// @param tokenIn The encoded data for the token to send
    /// @param tokenOut The encoded data for the token to receive
    /// @param receiver The address of the wallet that will receive the tokens
    /// @param data The call data to be sent to the shortcuts contract
    function safeRouteSingle(
        Token calldata tokenIn,
        Token calldata tokenOut,
        address receiver,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory response)
    {
        uint256 balance = _balance(tokenOut, receiver);
        response = routeSingle(tokenIn, data);
        _checkMinAmountOut(tokenOut, receiver, balance);
    }

    /// @notice Route multiple tokens via a call to the shortcuts contract and revert if there is insufficient tokens
    /// received
    /// @param tokensIn The encoded data for the tokens to send
    /// @param tokensOut The encoded data for the tokens to receive
    /// @param receiver The address of the wallet that will receive the tokens
    /// @param data The call data to be sent to the shortcuts contract
    function safeRouteMulti(
        Token[] calldata tokensIn,
        Token[] calldata tokensOut,
        address receiver,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory response)
    {
        uint256[] memory balances = new uint256[](tokensOut.length);
        for (uint256 i; i < tokensOut.length; ++i) {
            balances[i] = _balance(tokensOut[i], receiver);
        }

        response = routeMulti(tokensIn, data);

        for (uint256 i; i < tokensOut.length; ++i) {
            _checkMinAmountOut(tokensOut[i], receiver, balances[i]);
        }
    }

    /// @notice A function to execute a call on the shortcuts contract
    /// @param data The call data to be sent to the shortcuts contract
    function _execute(bytes calldata data) internal returns (bytes memory response) {
        bool success;
        (success, response) = shortcuts.call{ value: msg.value }(data);
        if (!success) {
            assembly {
                revert(add(response, 32), mload(response))
            }
        }
    }

    function _transfer(Token calldata token) internal returns (bool isNativeAsset) {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.ERC20) {
            (IERC20 erc20, uint256 amount) = abi.decode(token.data, (IERC20, uint256));
            erc20.safeTransferFrom(msg.sender, shortcuts, amount);
        } else if (tokenType == TokenType.Native) {
            // no need to get amount, it will come from msg.value
            isNativeAsset = true;
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            erc721.safeTransferFrom(msg.sender, shortcuts, tokenId);
        } else if (tokenType == TokenType.ERC1155) {
            (IERC1155 erc1155, uint256 tokenId, uint256 amount) = abi.decode(token.data, (IERC1155, uint256, uint256));
            erc1155.safeTransferFrom(msg.sender, shortcuts, tokenId, amount, "0x");
        } else {
            revert UnsupportedTokenType(tokenType);
        }
    }

    function _balance(Token calldata token, address receiver) internal view returns (uint256 balance) {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            balance = erc20.balanceOf(receiver);
        } else if (tokenType == TokenType.Native) {
            balance = receiver.balance;
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721,) = abi.decode(token.data, (IERC721, uint256));
            balance = erc721.balanceOf(receiver);
        } else if (tokenType == TokenType.ERC1155) {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            balance = erc1155.balanceOf(receiver, tokenId);
        } else {
            revert UnsupportedTokenType(tokenType);
        }
    }

    function _checkMinAmountOut(Token calldata token, address receiver, uint256 prevBalance) internal view {
        TokenType tokenType = token.tokenType;

        uint256 balance;
        uint256 minAmountOut;
        if (tokenType == TokenType.ERC20) {
            IERC20 erc20;
            (erc20, minAmountOut) = abi.decode(token.data, (IERC20, uint256));
            balance = erc20.balanceOf(receiver);
        } else if (tokenType == TokenType.Native) {
            (minAmountOut) = abi.decode(token.data, (uint256));
            balance = receiver.balance;
        } else if (tokenType == TokenType.ERC721) {
            IERC721 erc721;
            (erc721, minAmountOut) = abi.decode(token.data, (IERC721, uint256));
            balance = erc721.balanceOf(receiver);
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155 erc1155;
            uint256 tokenId;
            (erc1155, tokenId, minAmountOut) = abi.decode(token.data, (IERC1155, uint256, uint256));
            balance = erc1155.balanceOf(receiver, tokenId);
        } else {
            revert UnsupportedTokenType(tokenType);
        }

        uint256 amountOut = balance - prevBalance;
        if (amountOut < minAmountOut) revert AmountTooLow(token, amountOut, minAmountOut);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

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

interface IEnsoRouter {
    function routeSingle(
        Token calldata tokenIn,
        bytes calldata data
    ) external payable returns (bytes memory response);

    function routeMulti(
        Token[] calldata tokensIn,
        bytes calldata data
    ) external payable returns (bytes memory response);

    function safeRouteSingle(
        Token calldata tokenIn,
        Token calldata tokenOut,
        address receiver,
        bytes calldata data
    ) external payable returns (bytes memory response);

    function safeRouteMulti(
        Token[] calldata tokensIn,
        Token[] calldata tokensOut,
        address receiver,
        bytes calldata data
    ) external payable returns (bytes memory response);
}
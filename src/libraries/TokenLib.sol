// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// The canonical home of the Token type. EnsoRouter currently declares an identical
// type in IEnsoRouter.sol (kept untouched for now — audited); it should migrate to
// this one. Ordinals and encodings must stay byte-compatible with the router's.
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

/// Token accounting over the shared type: balances, approvals, and call value.
/// Encoding follows the router's conventions: ERC20 (IERC20, uint256), Native
/// (uint256), ERC721 (IERC721, uint256), ERC1155 (IERC1155, uint256 tokenId, uint256).
/// The second word is an amount or minimum in constraint contexts and a tokenId for
/// ERC721 transfers, exactly as EnsoRouter reads it.
library TokenLib {
    using SafeERC20 for IERC20;

    /// Strict, typed balance read — reverts on a non-conforming asset. For committed
    /// tokens on the execute path, where garbage should fail loudly.
    function balance(Token memory token, address account) internal view returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return account.balance;
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            return erc20.balanceOf(account);
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721,) = abi.decode(token.data, (IERC721, uint256));
            return erc721.balanceOf(account);
        } else {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return erc1155.balanceOf(account, tokenId);
        }
    }

    /// Grant or revoke a spender's pull rights over one delivered token. forceApprove:
    /// a reused address can hold a stale allowance from a previous incarnation, which
    /// breaks approve-from-nonzero tokens like USDT. Native is skipped; it travels as
    /// call value.
    function approve(Token memory token, address spender, bool grant) internal {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return;
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            erc20.forceApprove(spender, grant ? erc20.balanceOf(address(this)) : 0);
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            erc721.approve(grant ? spender : address(0), tokenId);
        } else {
            (IERC1155 erc1155,,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            erc1155.setApprovalForAll(spender, grant);
        }
    }

    /// Call value for the router: the full native balance when a native entry exists,
    /// zero otherwise — never chosen by the keeper.
    function value(Token[] memory tokens) internal view returns (uint256) {
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i].tokenType == TokenType.Native) {
                return address(this).balance;
            }
        }
        return 0;
    }
}

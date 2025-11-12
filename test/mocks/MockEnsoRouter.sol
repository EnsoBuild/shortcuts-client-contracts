// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Token, TokenType } from "../../../../src/interfaces/IEnsoRouter.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract MockEnsoShortcuts {
    receive() external payable { }
}

contract MockEnsoRouter {
    using SafeERC20 for IERC20;

    address public immutable shortcuts;
    bool private s_success;
    bytes private s_response;

    error WrongMsgValue(uint256 value, uint256 expectedAmount);
    error UnsupportedTokenType(TokenType tokenType);

    constructor() {
        shortcuts = address(new MockEnsoShortcuts());
    }

    function routeSingle(Token calldata tokenIn, bytes calldata) public payable returns (bytes memory response) {
        bool isNativeAsset = _transfer(tokenIn);
        if (!isNativeAsset && msg.value != 0) {
            revert WrongMsgValue(msg.value, 0);
        }
        response = s_response;

        if (!s_success) {
            assembly {
                revert(add(response, 32), mload(response))
            }
        }
        if (isNativeAsset) {
            shortcuts.call{ value: msg.value }("");
        }
    }

    function setRouteSingleResponse(bool _success, bytes memory _response) external {
        s_success = _success;
        s_response = _response;
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
}

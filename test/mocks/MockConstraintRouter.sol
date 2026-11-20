// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../src/interfaces/IEnsoRouter.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";

/// EnsoRouter's route entry points: pulls exactly the tokens it is given from the caller, as the
/// real router does, then pays configured outputs.
contract MockConstraintRouter is ERC1155Holder {
    struct Out {
        address token; // address(0) = native
        uint256 amount;
        address to;
    }

    Out[] private s_outs;
    bool public shouldRevert;
    bytes public lastData;
    uint256 public lastValue;
    uint256 public calls;
    Token[] private s_lastTokens;

    error MockRouterRevert();

    receive() external payable { }

    function routeSingle(Token calldata tokenIn, bytes calldata data) external payable returns (bytes memory) {
        Token[] memory tokens = new Token[](1);
        tokens[0] = tokenIn;
        return _route(tokens, data);
    }

    function routeMulti(Token[] calldata tokensIn, bytes calldata data) external payable returns (bytes memory) {
        return _route(tokensIn, data);
    }

    function addOut(address token, uint256 amount, address to) external {
        s_outs.push(Out(token, amount, to));
    }

    function clearOuts() external {
        delete s_outs;
    }

    function setRevert(bool value) external {
        shouldRevert = value;
    }

    function lastTokens() external view returns (Token[] memory) {
        return s_lastTokens;
    }

    function _route(Token[] memory tokens, bytes memory data) private returns (bytes memory) {
        if (shouldRevert) {
            revert MockRouterRevert();
        }
        ++calls;
        lastData = data;
        lastValue = msg.value;
        delete s_lastTokens;
        for (uint256 i; i < tokens.length; ++i) {
            s_lastTokens.push(tokens[i]);
            Token memory t = tokens[i];
            if (t.tokenType == TokenType.ERC20) {
                (address token, uint256 amount) = abi.decode(t.data, (address, uint256));
                IERC20(token).transferFrom(msg.sender, address(this), amount);
            } else if (t.tokenType == TokenType.ERC721) {
                (address token, uint256 id) = abi.decode(t.data, (address, uint256));
                IERC721(token).transferFrom(msg.sender, address(this), id);
            } else if (t.tokenType == TokenType.ERC1155) {
                (address token, uint256 id, uint256 amount) = abi.decode(t.data, (address, uint256, uint256));
                IERC1155(token).safeTransferFrom(msg.sender, address(this), id, amount, "");
            }
        }
        for (uint256 i; i < s_outs.length; ++i) {
            Out memory o = s_outs[i];
            if (o.token == address(0)) {
                (bool ok,) = o.to.call{ value: o.amount }("");
                require(ok, "native out failed");
            } else {
                IERC20(o.token).transfer(o.to, o.amount);
            }
        }
        return "";
    }
}

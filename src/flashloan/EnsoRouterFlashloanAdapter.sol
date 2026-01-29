// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { AbstractEnsoFlashloan, LenderProtocol } from "./AbstractEnsoFlashloan.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoRouterFlashloanAdapter is AbstractEnsoFlashloan {
    using SafeERC20 for IERC20;

    address public immutable router;

    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address router_,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    {
        router = router_;
    }

    function executeShortcut(
        address, // wallet not used for router
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] memory commands,
        bytes[] memory state,
        address token,
        uint256 amount
    )
        internal
        override
        returns (uint256 balanceBefore)
    {
        balanceBefore = IERC20(token).balanceOf(address(this)) - amount;

        IERC20(token).forceApprove(router, amount);
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(IERC20(token), amount) });

        bytes memory data =
            abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (accountId, requestId, commands, state));

        IEnsoRouter(router).routeSingle(tokenIn, data);
    }

    function executeShortcutMulti(
        address, // wallet not used for router
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] memory commands,
        bytes[] memory state,
        address[] memory tokens,
        uint256[] memory amounts
    )
        internal
        override
        returns (uint256[] memory balancesBefore)
    {
        uint256 length = tokens.length;
        balancesBefore = new uint256[](length);
        Token[] memory tokensIn = new Token[](length);

        for (uint256 i; i < length; ++i) {
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(address(this)) - amounts[i];

            IERC20(tokens[i]).forceApprove(router, amounts[i]);

            tokensIn[i] = Token({ tokenType: TokenType.ERC20, data: abi.encode(IERC20(tokens[i]), amounts[i]) });
        }

        bytes memory data =
            abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (accountId, requestId, commands, state));

        IEnsoRouter(router).routeMulti(tokensIn, data);
    }
}

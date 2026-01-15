// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { AbstractEnsoFlashloan, LenderProtocol } from "./AbstractEnsoFlashloan.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoWalletFlashloanAdapter is AbstractEnsoFlashloan {
    using SafeERC20 for IERC20;

    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    { }

    function executeShortcut(
        address wallet,
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
        IERC20(token).safeTransfer(wallet, amount);
        balanceBefore = IERC20(token).balanceOf(address(this));

        IEnsoWalletV2(wallet).executeShortcut(accountId, requestId, commands, state);
    }

    function executeShortcutMulti(
        address wallet,
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

        for (uint256 i; i < length; ++i) {
            IERC20(tokens[i]).safeTransfer(wallet, amounts[i]);
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        IEnsoWalletV2(wallet).executeShortcut(accountId, requestId, commands, state);
    }
}

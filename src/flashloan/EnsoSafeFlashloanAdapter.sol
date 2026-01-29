// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractEnsoFlashloan, LenderProtocol } from "./AbstractEnsoFlashloan.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ISafe } from "safe-smart-account-1.5.0/interfaces/ISafe.sol";
import { Enum } from "safe-smart-account-1.5.0/libraries/Enum.sol";

contract EnsoSafeFlashloanAdapter is AbstractEnsoFlashloan {
    using SafeERC20 for IERC20;

    error SafeExecutionFailed();

    address public immutable shortcuts;

    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address shortcuts_,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    {
        shortcuts = shortcuts_;
    }

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

        _executeOnSafe(wallet, accountId, requestId, commands, state);
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

        _executeOnSafe(wallet, accountId, requestId, commands, state);
    }

    function _executeOnSafe(
        address wallet,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] memory commands,
        bytes[] memory state
    )
        private
    {
        bytes memory data =
            abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (accountId, requestId, commands, state));

        bool success = ISafe(payable(wallet)).execTransactionFromModule(shortcuts, 0, data, Enum.Operation.DelegateCall);

        if (!success) {
            revert SafeExecutionFailed();
        }
    }
}

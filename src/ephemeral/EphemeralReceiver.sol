// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";

contract EphemeralReceiver {
    using SafeERC20 for IERC20;

    address private constant _NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event ExecutionSuccessful();
    event ExecutionFailed(bytes error);

    error TransferFailed(address receiver);
    
    constructor(address receiver, address token, uint256 amount, address target, bytes memory data) payable {
        // try to execute call
        uint256 value = msg.value;
        if (token == _NATIVE_ASSET) {
            value += amount;
        } else {
            IERC20(token).forceApprove(target, amount);
        }
        (bool success, bytes memory response) = target.call{ value: value }(data);
        if (success) {
            emit ExecutionSuccessful();
        } else {
            // if shortcut fails send funds to receiver
            emit ExecutionFailed(response);
            _transfer(token, receiver, amount);
        }
        // we done. destroy contract.
        selfdestruct(payable(msg.sender)); // return any remaining funds (should just be msg.value) to the factory (to be returned to the keeper)
    }

    function _transfer(address token, address receiver, uint256 amount) internal {
        if (token == _NATIVE_ASSET) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) revert TransferFailed(receiver);
        } else {
            IERC20(token).safeTransfer(receiver, amount);
        }
    }
}

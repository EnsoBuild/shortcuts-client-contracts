// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract TransferHelpers {
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 1;
    IERC20 private constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error IncorrectValue(uint256 expected, uint256 actual);
    error TransferFailed(address receiver);

    function transferWithLimit(
        IERC20 token,
        uint256 amount,
        uint256 maxAmount,
        address receiver,
        address feeReceiver
    )
        external
        payable
        returns (uint256)
    {
        if (token != _ETH && msg.value > 0) {
            revert IncorrectValue(0, msg.value);
        }
        if (token == _ETH && msg.value != amount) {
            revert IncorrectValue(amount, msg.value);
        }
        if (amount > 0) {
            if (amount > maxAmount && maxAmount != 0) {
                // send surplus to fee receiver
                uint256 surplus = amount - maxAmount;
                _transfer(token, feeReceiver, surplus);
                // update amount;
                amount = maxAmount;
            }
            // send remaining funds onward
            _transfer(token, receiver, amount);
        }
        return amount;
    }

    function _transfer(IERC20 token, address receiver, uint256 amount) internal {
        if (token == _ETH) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) {
                revert TransferFailed(receiver);
            }
        } else {
            token.safeTransferFrom(msg.sender, receiver, amount);
        }
    }
}

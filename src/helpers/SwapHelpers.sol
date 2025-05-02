// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Helper contract to update swap data on-chain
 */
contract SwapHelpers {
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 5;
    IERC20 private constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error IncorrectValue(uint256 expected, uint256 actual);
    error TransferFailed(address receiver);

    function swapWithLimit(
        address primary,
        address operator,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 maxAmountOut,
        address receiver,
        address feeReceiver,
        bytes memory data,
        uint256[] memory pointers
    )
        public
        payable
        returns (uint256 amountOut)
    {
        uint256 balanceBefore = _balance(tokenOut, receiver);
        _swap(primary, operator, tokenIn, amountIn, data, pointers);
        amountOut = _balance(tokenOut, address(this));
        if (maxAmountOut > 0 && amountOut > maxAmountOut) {
            uint256 fee = amountOut - maxAmountOut;
            _transfer(tokenOut, feeReceiver, fee);
            amountOut = maxAmountOut;
        }
        _transfer(tokenOut, receiver, amountOut);
        uint256 balanceAfter = _balance(tokenOut, receiver);
        amountOut = balanceAfter - balanceBefore;
    }

    function swap(
        address primary,
        address operator,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        address receiver,
        bytes memory data,
        uint256[] memory pointers
    )
        public
        payable
        returns (uint256 amountOut)
    {
        uint256 balanceBefore = _balance(tokenOut, receiver);
        _swap(primary, operator, tokenIn, amountIn, data, pointers);
        _transfer(tokenOut, receiver, _balance(tokenOut, address(this)));
        uint256 balanceAfter = _balance(tokenOut, receiver);
        amountOut = balanceAfter - balanceBefore;
    }

    function swap(
        address primary,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        address receiver,
        bytes memory data,
        uint256[] memory pointers
    )
        external
        payable
        returns (uint256)
    {
        return swap(primary, primary, tokenIn, tokenOut, amountIn, receiver, data, pointers);
    }

    function insertAmount(
        bytes memory data,
        uint256[] memory pointers,
        uint256 amount
    )
        public
        pure
        returns (bytes memory)
    {
        uint256 length = pointers.length;
        assembly {
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                let pointer := mload(add(pointers, mul(32, add(i, 1))))
                mstore(add(data, add(36, pointer)), amount)
            }
        }
        return data;
    }

    function _swap(
        address primary,
        address operator,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes memory data,
        uint256[] memory pointers
    )
        public
        payable
    {
        if (pointers.length != 0) insertAmount(data, pointers, amountIn);
        if (tokenIn == _ETH) {
            if (msg.value != amountIn) revert IncorrectValue(amountIn, msg.value);
        } else {
            if (msg.value != 0) revert IncorrectValue(0, msg.value);
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
            tokenIn.forceApprove(operator, amountIn);
        }
        (bool success, bytes memory response) = primary.call{ value: msg.value }(data);
        if (!success) {
            assembly {
                revert(add(response, 0x20), mload(response))
            }
        }
    }
    
    function _transfer(
        IERC20 token,
        address receiver,
        uint256 amount
    )
        internal
    {
        if (token == _ETH) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) revert TransferFailed(receiver);
        } else {
            token.safeTransfer(receiver, amount);
        }
    }

    function _balance(
        IERC20 token,
        address account
    )
        internal
        view
        returns (uint256 balance)
    {
        balance = token == _ETH
            ? account.balance
            : token.balanceOf(account);
    }

    receive() external payable { }
}

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
        returns (bytes memory)
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
        if (tokenOut == _ETH) {
            (success,) = receiver.call{ value: address(this).balance }("");
            if (!success) revert TransferFailed(receiver);
        } else {
            tokenOut.safeTransfer(receiver, tokenOut.balanceOf(address(this)));
        }
        return response;
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
        returns (bytes memory)
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

    receive() external payable { }
}

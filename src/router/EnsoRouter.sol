// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

struct Token {
    IERC20 token;
    uint256 amount;
}

contract EnsoRouter {
    using SafeERC20 for IERC20;

    IERC20 private constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error WrongValue(uint256 value, uint256 amount);
    error AmountTooLow(address token);
    error Duplicate(address token);


    // @notice Route a single token via a call to an external contract
    // @param tokenIn The address of the token to send
    // @param amountIn The amount of the token to send
    // @param target The address of the target contract
    // @param data The call data to be sent to the target
    function routeSingle(
        IERC20 tokenIn,
        uint256 amountIn,
        address target,
        bytes calldata data
    ) public payable returns (bytes memory response) {
        if (tokenIn == _ETH) {
            if (msg.value != amountIn) revert WrongValue(msg.value, amountIn);
        } else {
            if (msg.value != 0) revert WrongValue(msg.value, 0);
            tokenIn.safeTransferFrom(msg.sender, target, amountIn);
        }
        response = _execute(target, msg.value, data);
    }

    // @notice Route multiple tokens via a call to an external contract
    // @param tokensIn The addresses and amounts of the tokens to send
    // @param target The address of the target contract
    // @param data The call data to be sent to the target
    function routeMulti(
        Token[] calldata tokensIn,
        address target,
        bytes calldata data
    ) public payable returns (bytes memory response) {
        bool ethFlag;
        IERC20 tokenIn;
        uint256 amountIn;
        for (uint256 i; i < tokensIn.length; ++i) {
            tokenIn = tokensIn[i].token;
            amountIn = tokensIn[i].amount;
            if (tokenIn == _ETH) {
                if (ethFlag) revert Duplicate(address(_ETH));
                ethFlag = true;
                if (msg.value != amountIn) revert WrongValue(msg.value, amountIn);
            } else {
                tokenIn.safeTransferFrom(msg.sender, target, amountIn);
            }
        }
        if (!ethFlag && msg.value != 0) revert WrongValue(msg.value, 0);
        
        response = _execute(target, msg.value, data);
    }

    // @notice Route a single token via a call to an external contract and revert if there is insufficient token received
    // @param tokenIn The address of the token to send
    // @param tokenOut The address of the token to receive
    // @param amountIn The amount of the token to send
    // @param minAmountOut The minimum amount of the token to receive
    // @param receiver The address of the wallet that will receive the tokens
    // @param target The address of the target contract
    // @param data The call data to be sent to the target
    function safeRouteSingle(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        address target,
        bytes calldata data
    ) external payable returns (bytes memory response) {
        uint256 balance = tokenOut == _ETH ? receiver.balance : tokenOut.balanceOf(receiver);
        response = routeSingle(tokenIn, amountIn, target, data);
        uint256 amountOut;
        if (tokenOut == _ETH) {
            amountOut = receiver.balance - balance;
        } else {
            amountOut = tokenOut.balanceOf(receiver) - balance;
        }
        if (amountOut < minAmountOut) revert AmountTooLow(address(tokenOut));
    }

    // @notice Route multiple tokens via a call to an external contract and revert if there is insufficient tokens received
    // @param tokensIn The addresses and amounts of the tokens to send
    // @param tokensOut The addresses and minimum amounts of the tokens to receive
    // @param receiver The address of the wallet that will receive the tokens
    // @param target The address of the target contract
    // @param data The call data to be sent to the target
    function safeRouteMulti(
        Token[] calldata tokensIn,
        Token[] calldata tokensOut,
        address receiver,
        address target,
        bytes calldata data
    ) external payable returns (bytes memory response) {
        uint256 length = tokensOut.length;
        uint256[] memory balances = new uint256[](length);

        IERC20 tokenOut;
        for (uint256 i; i < length; ++i) {
            tokenOut = tokensOut[i].token;
            balances[i] = tokenOut == _ETH ? receiver.balance : tokenOut.balanceOf(receiver);
        }

        response = routeMulti(tokensIn, target, data);

        uint256 amountOut;
        for (uint256 i; i < length; ++i) {
            tokenOut = tokensOut[i].token;
            if (tokenOut == _ETH) {
                amountOut = receiver.balance - balances[i];
            } else {
                amountOut = tokenOut.balanceOf(receiver) - balances[i];
            }
            if (amountOut < tokensOut[i].amount) revert AmountTooLow(address(tokenOut));
        }
    }

    // @notice A function to execute an arbitrary call on another contract
    // @param target The address of the target contract
    // @param value The ether value that is to be sent with the call
    // @param data The call data to be sent to the target
    function _execute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal returns (bytes memory response) {
        bool success;
        (success, response) = target.call{value: value}(data);
        if (!success) {
            assembly{
                revert(add(response, 32), mload(response))
            }
        }
    }
}

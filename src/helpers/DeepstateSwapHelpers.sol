// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { IDeepstateV1 } from "../interfaces/IDeepstateV1.sol";

/// @title Deepstate Swap Helpers
/// @notice Adapts a Deepstate route to Enso's pull-call-forward swap convention.
/// @dev The helper is deliberately separate from `SwapHelpers`, whose deployed bytecode is part of
/// Enso's existing audited surface. Every route leg is forced to `noRest` so a partial swap cannot
/// leave a maker order owned by this transient helper contract. Unspent input and all output are
/// forwarded to `receiver` before the call returns. The route must net intermediate assets to zero,
/// and its ERC-20 tokens must use conventional balance and transfer semantics.
contract DeepstateSwapHelpers {
    using SafeERC20 for IERC20;

    uint256 public constant VERSION = 1;

    /// @dev Native-token sentinel used by Enso's existing swap helpers. Deepstate route entries
    /// themselves continue to identify native ETH as `address(0)`.
    IERC20 private constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error IncorrectValue(uint256 expected, uint256 actual);
    error InvalidEngine();
    error InvalidPair();
    error InvalidReceiver();
    error InvalidRoute();
    error InvalidToken();
    error TransferFailed(address receiver);

    /// @notice Execute an atomic Deepstate route and forward its result.
    /// @param deepstate Deepstate engine selected by the route builder.
    /// @param tokenIn Route input token, or Enso's native-token sentinel.
    /// @param tokenOut Route output token, or Enso's native-token sentinel.
    /// @param amountIn Maximum input made available to the route.
    /// @param receiver Account receiving both output and any unspent input.
    /// @param fills Sequential Deepstate fill legs. Their `noRest` fields are overridden to true.
    /// @return amountOut Increase in the receiver's output-token balance.
    /// @dev Enso's `safeRouteSingle` supplies the aggregate minimum-output check around this call.
    function swap(
        IDeepstateV1 deepstate,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        address receiver,
        IDeepstateV1.FillParams[] calldata fills
    )
        external
        payable
        returns (uint256 amountOut)
    {
        if (address(deepstate) == address(0)) {
            revert InvalidEngine();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
        if (address(tokenIn) == address(0) || address(tokenOut) == address(0)) {
            revert InvalidToken();
        }
        if (tokenIn == tokenOut) {
            revert InvalidPair();
        }
        if (fills.length == 0) {
            revert InvalidRoute();
        }

        uint256 receiverBalanceBefore = _balance(tokenOut, receiver);
        uint256 inputBalanceBefore = _balance(tokenIn, address(this));
        uint256 outputBalanceBefore = _balance(tokenOut, address(this));

        if (tokenIn == _ETH) {
            if (msg.value != amountIn) {
                revert IncorrectValue(amountIn, msg.value);
            }
            inputBalanceBefore -= msg.value;
        } else {
            if (msg.value != 0) {
                revert IncorrectValue(0, msg.value);
            }
            tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
            tokenIn.forceApprove(address(deepstate), amountIn);
        }

        IDeepstateV1.FillParams[] memory route = fills;
        for (uint256 i; i < route.length;) {
            route[i].noRest = true;
            unchecked {
                ++i;
            }
        }

        deepstate.fillRoute{ value: msg.value }(route);

        if (tokenIn != _ETH) {
            tokenIn.forceApprove(address(deepstate), 0);
        }

        uint256 output = _balance(tokenOut, address(this)) - outputBalanceBefore;
        if (output != 0) {
            _transfer(tokenOut, receiver, output);
        }
        uint256 unspentInput = _balance(tokenIn, address(this)) - inputBalanceBefore;
        if (unspentInput != 0) {
            _transfer(tokenIn, receiver, unspentInput);
        }

        amountOut = _balance(tokenOut, receiver) - receiverBalanceBefore;
    }

    function _transfer(IERC20 token, address receiver, uint256 amount) private {
        if (token == _ETH) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) {
                revert TransferFailed(receiver);
            }
        } else {
            token.safeTransfer(receiver, amount);
        }
    }

    function _balance(IERC20 token, address account) private view returns (uint256 balance) {
        balance = token == _ETH ? account.balance : token.balanceOf(account);
    }

    receive() external payable { }
}

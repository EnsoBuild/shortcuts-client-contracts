// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPropAMM } from "../../src/interfaces/IPropAMM.sol";
import { MockERC20 } from "./MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Fixed-rate pAMM that mints its output. `rate` is tokenOut per tokenIn, scaled by 1e18.
contract MockPropAMM is IPropAMM {
    enum Mode {
        Normal,
        QuoteReverts,
        SwapReverts,
        PaysNothing,
        PaysHalf
    }

    uint256 public rate;
    Mode public mode;
    uint256 public swapCalls;
    uint256 public lastMinAmountOut;

    constructor(uint256 rate_) {
        rate = rate_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setRate(uint256 rate_) external {
        rate = rate_;
    }

    function isActive(address, address) external view returns (bool) {
        return mode != Mode.QuoteReverts;
    }

    function getPairs() external pure returns (TokenPair[] memory pairs) {
        return pairs;
    }

    function quote(address, address, uint256 amountIn) external view returns (uint256) {
        require(mode != Mode.QuoteReverts, "MockPropAMM: inactive");
        return amountIn * rate / 1e18;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    )
        external
        returns (uint256 amountOut)
    {
        swapCalls++;
        lastMinAmountOut = minAmountOut;
        require(mode != Mode.SwapReverts, "MockPropAMM: stale");
        require(deadline >= block.timestamp, "MockPropAMM: expired");
        require(IERC20(tokenIn).balanceOf(address(this)) >= amountIn, "MockPropAMM: unpaid");

        amountOut = amountIn * rate / 1e18;
        if (mode == Mode.PaysNothing) {
            return amountOut;
        }
        if (mode == Mode.PaysHalf) {
            amountOut /= 2;
        } else {
            require(amountOut >= minAmountOut, "MockPropAMM: slippage");
        }
        MockERC20(tokenOut).mint(recipient, amountOut);
        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, recipient);
    }
}

/// @dev Fixed-rate two-coin Curve pool exposing both index flavours of `get_dy` and `exchange`.
abstract contract MockCurvePoolBase {
    address[2] internal _coins;
    uint256 public immutable rate; // coins[1] per coins[0], scaled by 1e18

    constructor(address coin0, address coin1, uint256 rate_) {
        _coins = [coin0, coin1];
        rate = rate_;
    }

    function get_dy(int128 i, int128 j, uint256 dx) public view returns (uint256) {
        return _dy(uint256(uint128(i)), uint256(uint128(j)), dx);
    }

    function get_dy(uint256 i, uint256 j, uint256 dx) public view returns (uint256) {
        return _dy(i, j, dx);
    }

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256) {
        return _exchange(uint256(uint128(i)), uint256(uint128(j)), dx, minDy);
    }

    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) external returns (uint256) {
        return _exchange(i, j, dx, minDy);
    }

    function _dy(uint256 i, uint256 j, uint256 dx) internal view returns (uint256) {
        require(i != j && i < 2 && j < 2, "MockCurve: index");
        return i == 0 ? dx * rate / 1e18 : dx * 1e18 / rate;
    }

    function _exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) internal returns (uint256 dy) {
        dy = _dy(i, j, dx);
        require(dy >= minDy, "MockCurve: slippage");
        IERC20(_coins[i]).transferFrom(msg.sender, address(this), dx);
        IERC20(_coins[j]).transfer(msg.sender, dy);
    }
}

/// @dev A Curve pool with the usual `coins(uint256)` getter.
contract MockCurvePool is MockCurvePoolBase {
    constructor(address coin0, address coin1, uint256 rate_) MockCurvePoolBase(coin0, coin1, rate_) { }

    function coins(uint256 i) external view returns (address) {
        return _coins[i];
    }
}

/// @dev Pulls tokens for `MockRouter`, so the approved operator differs from the called target.
contract MockTokenPuller {
    function pull(address token, address from, address to, uint256 amount) external {
        IERC20(token).transferFrom(from, to, amount);
    }
}

/// @dev Fixed-rate router that pulls its input by approval and mints its output to `recipient`.
contract MockRouter {
    uint256 public immutable rate; // tokenOut per tokenIn, scaled by 1e18
    MockTokenPuller public immutable puller;
    // Pulls `amountIn / pullDivisor`, as a router filling part of the order would.
    uint256 public pullDivisor = 1;
    bool public reverts;

    constructor(uint256 rate_, MockTokenPuller puller_) {
        rate = rate_;
        puller = puller_;
    }

    function setPullDivisor(uint256 pullDivisor_) external {
        pullDivisor = pullDivisor_;
    }

    function setReverts(bool reverts_) external {
        reverts = reverts_;
    }

    function swapExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    )
        external
        returns (uint256 amountOut)
    {
        require(!reverts, "MockRouter: failed");
        uint256 pulled = amountIn / pullDivisor;
        if (address(puller) == address(0)) {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), pulled);
        } else {
            puller.pull(tokenIn, msg.sender, address(this), pulled);
        }
        amountOut = pulled * rate / 1e18;
        require(amountOut >= minAmountOut, "MockRouter: slippage");
        MockERC20(tokenOut).mint(recipient, amountOut);
    }
}

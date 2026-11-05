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

interface IV3Callback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;

    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

/// @dev Fixed-rate V3-style pool. Pays out first, then calls back for the input, like Uniswap V3.
/// `maxAmountIn` caps how much it fills, as a price limit would.
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint256 public immutable rate; // token1 per token0, scaled by 1e18
    bool public immutable pancake;
    uint256 public maxAmountIn = type(uint256).max;
    uint256 public overcharge;
    // When set, sent to the callback in place of the swap's `data`, as a hostile pool could.
    bytes public forgedData;

    constructor(address tokenA, address tokenB, uint256 rate_, bool pancake_) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        rate = rate_;
        pancake = pancake_;
    }

    function setMaxAmountIn(uint256 maxAmountIn_) external {
        maxAmountIn = maxAmountIn_;
    }

    function setOvercharge(uint256 overcharge_) external {
        overcharge = overcharge_;
    }

    function setForgedData(bytes calldata forgedData_) external {
        forgedData = forgedData_;
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1)
    {
        require(amountSpecified > 0, "MockV3: exact input only");
        uint256 amountIn = uint256(amountSpecified);
        if (amountIn > maxAmountIn) {
            amountIn = maxAmountIn;
        }
        uint256 amountOut = zeroForOne ? amountIn * rate / 1e18 : amountIn * 1e18 / rate;
        uint256 charged = amountIn + overcharge;

        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        IERC20(tokenOut).transfer(recipient, amountOut);
        (amount0, amount1) = zeroForOne ? (int256(charged), -int256(amountOut)) : (-int256(amountOut), int256(charged));

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
        bytes memory callbackData = data;
        if (forgedData.length != 0) {
            callbackData = forgedData;
        }
        if (pancake) {
            IV3Callback(msg.sender).pancakeV3SwapCallback(amount0, amount1, callbackData);
        } else {
            IV3Callback(msg.sender).uniswapV3SwapCallback(amount0, amount1, callbackData);
        }
        require(IERC20(tokenIn).balanceOf(address(this)) >= balanceBefore + charged, "MockV3: unpaid");
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

/// @dev A pre-2021 Curve pool whose `coins` getter takes `int128`.
contract MockCurveLegacyPool is MockCurvePoolBase {
    constructor(address coin0, address coin1, uint256 rate_) MockCurvePoolBase(coin0, coin1, rate_) { }

    function coins(int128 i) external view returns (address) {
        return _coins[uint256(uint128(i))];
    }
}

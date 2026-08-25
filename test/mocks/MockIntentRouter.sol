// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token } from "../../src/libraries/TokenLib.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IContextProbe {
    function context() external view returns (bytes memory route, Token[] memory sweep, address keeper, address router);
}

/// Implements the router's route entry points, records what the executor sent
/// (including the live-amounted tokensIn), and performs configurable side effects:
/// pull a token via transferFrom (exercises the approval epilogue), send an output
/// token (exercises CONSTRAINED outcome measurement), probe the factory's transient
/// context mid-call, or revert (exercises bubbling).
contract MockIntentRouter {
    Token[] public lastTokensIn;
    bytes public lastData;
    uint256 public lastValue;
    address public lastCaller;
    uint256 public lastAllowance;

    address public pullToken;
    uint256 public pullAmount;
    address public outToken;
    uint256 public outAmount;
    uint256 public outNativeAmount;
    address public outReceiver;
    bool public shouldRevert;
    address public probe;

    bytes public probedRoute;
    Token[] public probedSweep;
    address public probedKeeper;
    address public probedRouter;

    error MockRouterRevert();

    receive() external payable { }

    function routeSingle(Token calldata tokenIn, bytes calldata data) external payable returns (bytes memory) {
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = tokenIn;
        return _record(tokensIn, data);
    }

    function routeMulti(Token[] calldata tokensIn, bytes calldata data) external payable returns (bytes memory) {
        return _record(tokensIn, data);
    }

    function _record(Token[] memory tokensIn, bytes memory data) private returns (bytes memory) {
        if (shouldRevert) {
            revert MockRouterRevert();
        }
        lastTokensIn = tokensIn;
        lastData = data;
        lastValue = msg.value;
        lastCaller = msg.sender;
        if (pullToken != address(0)) {
            lastAllowance = IERC20(pullToken).allowance(msg.sender, address(this));
            IERC20(pullToken).transferFrom(msg.sender, address(this), pullAmount);
        }
        if (probe != address(0)) {
            (probedRoute, probedSweep, probedKeeper, probedRouter) = IContextProbe(probe).context();
        }
        if (outToken != address(0)) {
            IERC20(outToken).transfer(outReceiver, outAmount);
        }
        if (outNativeAmount > 0) {
            (bool success,) = outReceiver.call{ value: outNativeAmount }("");
            require(success, "native out failed");
        }
        return "";
    }

    function lastTokensInLength() external view returns (uint256) {
        return lastTokensIn.length;
    }

    function setPull(address token, uint256 amount) external {
        pullToken = token;
        pullAmount = amount;
    }

    function setOut(address token, uint256 amount, address to) external {
        outToken = token;
        outAmount = amount;
        outReceiver = to;
    }

    function setOutNative(uint256 amount, address to) external {
        outNativeAmount = amount;
        outReceiver = to;
    }

    function setRevert(bool value) external {
        shouldRevert = value;
    }

    function setProbe(address factory) external {
        probe = factory;
    }

    function probedSweepLength() external view returns (uint256) {
        return probedSweep.length;
    }
}

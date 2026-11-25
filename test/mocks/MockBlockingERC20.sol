// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { MockERC20 } from "./MockERC20.sol";

/// A token with a blocklist, as USDC and USDT have: a blocked account can't send or receive.
contract MockBlockingERC20 is MockERC20 {
    mapping(address account => bool) public blocked;

    constructor(string memory name, string memory symbol) MockERC20(name, symbol) { }

    function setBlocked(address account, bool value) external {
        blocked[account] = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[from] && !blocked[to], "blocked");
        super._update(from, to, value);
    }
}

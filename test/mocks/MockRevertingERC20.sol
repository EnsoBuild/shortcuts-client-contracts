// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

/// Reports a balance but reverts on transfer — a sweep must tolerate it.
contract MockRevertingERC20 {
    function balanceOf(address) external pure returns (uint256) {
        return 1e18;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("NO");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

contract ERC20Helpers {
    uint256 public constant VERSION = 1;

    // This dumb function is for those ERC20s that return bytes with incorrect length for their balanceOf function
    function balanceOf(IERC20 token, address owner) external view returns (uint256 balance) {
        balance = token.balanceOf(owner);
    }
}

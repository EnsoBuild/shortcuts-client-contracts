// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

/// A transfer that succeeds but returns a non-canonical 32-byte word (2 instead of
/// true). abi.decode(ret, (bool)) reverts on it; a tolerant helper must not.
contract MockDirtyBoolERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (uint256) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return 2; // non-canonical "true"
    }
}

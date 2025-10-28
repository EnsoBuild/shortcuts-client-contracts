// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockVault is ERC20 {
    ERC20 public immutable token;

    constructor(string memory name, string memory symbol, address token_) ERC20(name, symbol) {
        token = ERC20(token_);
    }

    function deposit(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function redeem(uint256 amount) public {
        if (amount > balanceOf(msg.sender)) {
            revert();
        }
        _burn(msg.sender, amount);
        token.transfer(msg.sender, amount);
    }
}

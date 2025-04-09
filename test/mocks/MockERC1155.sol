// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1155 } from "openzeppelin-contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor(string memory uri) ERC1155(uri) { }

    function mint(address to, uint256 tokenId, uint256 amount) public {
        _mint(to, tokenId, amount, "0x");
    }
}

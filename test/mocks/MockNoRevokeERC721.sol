// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { ERC721 } from "openzeppelin-contracts/token/ERC721/ERC721.sol";

/// An ERC721 that rejects clearing an approval — a real anti-pattern. A revoke
/// swallowed against this collection while the token is still held would leave a
/// live approval keyed to the reusable CREATE2 address.
contract MockNoRevokeERC721 is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) { }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function approve(address to, uint256 tokenId) public override {
        require(to != address(0), "zero approve");
        super.approve(to, tokenId);
    }
}

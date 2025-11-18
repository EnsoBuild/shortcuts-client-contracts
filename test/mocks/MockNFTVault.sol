// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC721 } from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import { ERC721Holder } from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

contract MockNFTVault is ERC721, ERC721Holder {
    ERC721 public immutable nft;

    constructor(string memory name, string memory symbol, address nft_) ERC721(name, symbol) {
        nft = ERC721(nft_);
    }

    function deposit(uint256 tokenId) public {
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        _safeMint(msg.sender, tokenId);
    }

    function redeem(uint256 tokenId) public {
        if (ownerOf(tokenId) != msg.sender) {
            revert();
        }
        if (nft.ownerOf(tokenId) != address(this)) {
            revert();
        }
        _burn(tokenId);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }
}

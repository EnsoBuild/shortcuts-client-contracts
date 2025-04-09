// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC1155, IERC1155, IERC1155MetadataURI } from "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import { ERC1155Holder, IERC1155Receiver } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockMultiVault is ERC1155, ERC1155Holder {
    ERC1155 public immutable token;

    constructor(string memory uri, address token_) ERC1155(uri) {
        token = ERC1155(token_);
    }

    function deposit(uint256 tokenId, uint256 amount) public {
        token.safeTransferFrom(msg.sender, address(this), tokenId, amount, "0x");
        _mint(msg.sender, tokenId, amount, "0x");
    }

    function redeem(uint256 tokenId, uint256 amount) public {
        if (amount > balanceOf(msg.sender, tokenId)) revert();
        _burn(msg.sender, tokenId, amount);
        token.safeTransferFrom(address(this), msg.sender, tokenId, amount, "0x");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC1155Holder)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC1155).interfaceId
            || interfaceId == type(IERC1155MetadataURI).interfaceId || super.supportsInterface(interfaceId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract NftHelpers {
    uint256 public constant VERSION = 1;

    error OwnerMismatch(address nft, uint256 tokenId, address expected, address actual);
    error NotStashed(address caller, bytes32 key);

    // Reverts unless `owner` holds `tokenId`: an on-chain custody guard, the NFT counterpart of a minAmountOut check.
    // A burned or nonexistent id reverts in ownerOf.
    function checkOwner(IERC721 nft, uint256 tokenId, address owner) external view {
        address actual = nft.ownerOf(tokenId);
        if (actual != owner) {
            revert OwnerMismatch(address(nft), tokenId, owner, actual);
        }
    }

    // Hands a value from a nested shortcut (e.g. an id minted inside a flashloan callback) to its parent, which runs
    // as the same caller. Keyed by caller, so executors never share slots; cleared at the end of the transaction.
    function stash(bytes32 key, uint256 value) external {
        bytes32 slot = _slot(msg.sender, key);
        assembly ("memory-safe") {
            tstore(slot, value)
            tstore(add(slot, 1), 1)
        }
    }

    // Reverts when nothing was stashed under `key` in this transaction, so a missing value is never read as 0.
    function load(bytes32 key) external view returns (uint256 value) {
        bytes32 slot = _slot(msg.sender, key);
        uint256 isSet;
        assembly ("memory-safe") {
            value := tload(slot)
            isSet := tload(add(slot, 1))
        }
        if (isSet == 0) {
            revert NotStashed(msg.sender, key);
        }
    }

    function _slot(address caller, bytes32 key) private pure returns (bytes32) {
        return keccak256(abi.encode(caller, key));
    }
}

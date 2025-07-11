// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

abstract contract Withdrawable is ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    address public receiver;
    IERC20 private constant _NATIVE_ASSET = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error OnlyReceiver(address sender);
    error ReceiverNotSet();
    error WithdrawFailed();

    modifier onlyReceiver() {
        if (receiver == address(0)) revert ReceiverNotSet();
        if (msg.sender != receiver) revert OnlyReceiver(msg.sender);
        _;
    }

    // @notice Withdraw native asset from this contract to the receiver
    function withdrawNative() external onlyReceiver {
        _withdrawNative();
    }

    // @notice Withdraw ERC20s
    // @param erc20s An array of erc20 addresses
    function withdrawERC20s(IERC20[] calldata erc20s) external onlyReceiver {
        for (uint256 i; i < erc20s.length; ++i) {
            _withdrawERC20(erc20s[i]);
        }
    }

    // @notice Withdraw multiple ERC721 ids for a single ERC721 contract
    // @param erc721 The address of the ERC721 contract
    // @param ids An array of ids that are to be withdrawn
    function withdrawERC721s(IERC721 erc721, uint256[] calldata ids) external onlyReceiver {
        _withdrawERC721s(erc721, ids);
    }

    // @notice Withdraw multiple ERC1155 ids for a single ERC1155 contract
    // @param erc1155 The address of the ERC155 contract
    // @param ids An array of ids that are to be withdrawn
    // @param amounts An array of amounts per id
    function withdrawERC1155s(
        IERC1155 erc1155,
        uint256[] calldata ids,
        uint256[] calldata amounts
    )
        external
        onlyReceiver
    {
        _withdrawERC1155s(erc1155, ids, amounts);
    }

    function _withdrawToken(IERC20 token) internal {
        if (token == _NATIVE_ASSET) {
            _withdrawNative();
        } else {
            _withdrawERC20(token);
        }
    }

    function _withdrawNative() internal {
        (bool success,) = receiver.call{ value: address(this).balance }("");
        if (!success) revert WithdrawFailed();
    }

    function _withdrawERC20(IERC20 erc20) internal {
        erc20.safeTransfer(receiver, erc20.balanceOf(address(this)));
    }

    function _withdrawERC721s(IERC721 erc721, uint256[] memory ids) internal {
        for (uint256 i; i < ids.length; ++i) {
            erc721.safeTransferFrom(address(this), receiver, ids[i]);
        }
    }

    function _withdrawERC1155s(IERC1155 erc1155, uint256[] memory ids, uint256[] memory amounts) internal {
        // safeBatchTransferFrom will validate the array lengths
        erc1155.safeBatchTransferFrom(address(this), receiver, ids, amounts, "");
    }
}

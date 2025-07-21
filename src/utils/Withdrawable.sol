// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

abstract contract Withdrawable is ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    IERC20 private constant _NATIVE_ASSET = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error WithdrawFailed();

    // @notice Withdraw native asset from this contract to the owner
    function withdrawNative() external {
        _checkOwner();
        _withdrawNative(address(this).balance);
    }

    // @notice Withdraw ERC20s
    // @param erc20s An array of erc20 addresses
    function withdrawERC20s(IERC20[] calldata erc20s) external {
        _checkOwner();
        for (uint256 i; i < erc20s.length; ++i) {
            _withdrawERC20(erc20s[i], erc20s[i].balanceOf(address(this)));
        }
    }

    // @notice Withdraw multiple ERC721 ids for a single ERC721 contract
    // @param erc721 The address of the ERC721 contract
    // @param ids An array of ids that are to be withdrawn
    function withdrawERC721s(IERC721 erc721, uint256[] calldata ids) external {
        _checkOwner();
        _withdrawERC721s(erc721, ids);
    }

    // @notice Withdraw multiple ERC1155 ids for a single ERC1155 contract
    // @param erc1155 The address of the ERC155 contract
    // @param ids An array of ids that are to be withdrawn
    // @param amounts An array of amounts per id
    function withdrawERC1155s(IERC1155 erc1155, uint256[] calldata ids, uint256[] calldata amounts) external {
        _checkOwner();
        _withdrawERC1155s(erc1155, ids, amounts);
    }

    function owner() public view virtual returns (address);

    function _checkOwner() internal view virtual;

    function _withdrawToken(IERC20 token, uint256 amount) internal {
        if (token == _NATIVE_ASSET) {
            _withdrawNative(amount);
        } else {
            _withdrawERC20(token, amount);
        }
    }

    function _withdrawNative(uint256 amount) internal {
        (bool success,) = owner().call{ value: amount }("");
        if (!success) revert WithdrawFailed();
    }

    function _withdrawERC20(IERC20 erc20, uint256 amount) internal {
        erc20.safeTransfer(owner(), amount);
    }

    function _withdrawERC721s(IERC721 erc721, uint256[] memory ids) internal {
        for (uint256 i; i < ids.length; ++i) {
            erc721.safeTransferFrom(address(this), owner(), ids[i]);
        }
    }

    function _withdrawERC1155s(IERC1155 erc1155, uint256[] memory ids, uint256[] memory amounts) internal {
        // safeBatchTransferFrom will validate the array lengths
        erc1155.safeBatchTransferFrom(address(this), owner(), ids, amounts, "");
    }
}

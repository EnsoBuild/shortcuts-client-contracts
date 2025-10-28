// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { IEnsoWalletV2Factory } from "../interfaces/IEnsoWalletV2Factory.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { LibClone } from "solady/utils/LibClone.sol";

/// @title EnsoWalletV2Factory
/// @author Enso
/// @notice Factory for deploying deterministic Enso Wallet V2 instances using minimal clones
contract EnsoWalletV2Factory is IEnsoWalletV2Factory {
    using LibClone for address;
    using SafeERC20 for IERC20;

    address public immutable IMPLEMENTATION;

    constructor(address implementation) {
        IMPLEMENTATION = implementation;
    }

    /// @inheritdoc IEnsoWalletV2Factory
    function deploy(address account) external returns (address wallet) {
        return _deploy(account);
    }

    /// @inheritdoc IEnsoWalletV2Factory
    function deployAndExecute(
        Token[] calldata tokensIn,
        bytes calldata data
    )
        external
        payable
        returns (address wallet, bytes memory response)
    {
        return _deployAndExecute(tokensIn, data);
    }

    /// @inheritdoc IEnsoWalletV2Factory
    function getAddress(address account) external view returns (address) {
        bytes32 salt = _getSalt(account);
        return IMPLEMENTATION.predictDeterministicAddress(salt, address(this));
    }

    function _deployAndExecute(
        Token[] calldata tokensIn,
        bytes calldata data
    )
        private
        returns (address wallet, bytes memory response)
    {
        // strictly only msg.sender can deploy and execute
        wallet = _deploy(msg.sender);

        bool isNativeAsset;
        for (uint256 i = 0; i < tokensIn.length; i++) {
            if (_transfer(tokensIn[i], wallet)) {
                if (isNativeAsset) {
                    revert EnsoWalletV2Factory_DuplicateNativeAsset();
                }
                isNativeAsset = true;
            }
        }
        if (!isNativeAsset && msg.value != 0) {
            revert EnsoWalletV2Factory_WrongMsgValue(msg.value, 0);
        }

        bool success;
        (success, response) = wallet.call{ value: msg.value }(data);
        if (!success) {
            if (response.length > 0) {
                assembly ("memory-safe") {
                    revert(add(0x20, response), mload(response))
                }
            }
            revert EnsoWalletV2Factory_ExecutionFailed();
        }
    }

    function _deploy(address account) private returns (address wallet) {
        bytes32 salt = _getSalt(account);
        wallet = IMPLEMENTATION.predictDeterministicAddress(salt, address(this));
        if (wallet.code.length == 0) {
            IMPLEMENTATION.cloneDeterministic(salt);
            IEnsoWalletV2(wallet).initialize(account);
            emit EnsoWalletV2Deployed(wallet, account);
        }
    }

    function _transfer(Token calldata token, address receiver) private returns (bool isNativeAsset) {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.ERC20) {
            (IERC20 erc20, uint256 amount) = abi.decode(token.data, (IERC20, uint256));
            erc20.safeTransferFrom(msg.sender, receiver, amount);
        } else if (tokenType == TokenType.Native) {
            // no need to get amount, it will come from msg.value
            isNativeAsset = true;
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            erc721.safeTransferFrom(msg.sender, receiver, tokenId);
        } else if (tokenType == TokenType.ERC1155) {
            (IERC1155 erc1155, uint256 tokenId, uint256 amount) = abi.decode(token.data, (IERC1155, uint256, uint256));
            erc1155.safeTransferFrom(msg.sender, receiver, tokenId, amount, "0x");
        } else {
            revert EnsoWalletV2Factory_UnsupportedTokenType(tokenType);
        }
    }

    function _getSalt(address account) private pure returns (bytes32) {
        /// forge-lint: disable-next-item(asm-keccak256)
        return keccak256(abi.encode(account));
    }
}

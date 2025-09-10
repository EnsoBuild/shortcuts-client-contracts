// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";

import { IERC4337CloneInitializer } from "./interfaces/IERC4337CloneInitializer.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract ERC4337CloneFactory {
    using LibClone for address;
    using SafeERC20 for IERC20;

    address public immutable implementation;
    address public immutable entryPoint;

    event CloneDeployed(address clone, address account, address signer);

    error UnsupportedTokenType(TokenType tokenType);
    error WrongMsgValue(uint256 value, uint256 expectedAmount);
    error AlreadyDeployed();

    constructor(address implementation_, address entryPoint_) {
        implementation = implementation_;
        entryPoint = entryPoint_;
    }

    function deploy(address account) external returns (address clone) {
        return _deploy(account, account);
    }

    function deployAndExecute(
        address account,
        Token calldata tokenIn,
        bytes calldata data
    )
        external
        payable
        returns (address clone)
    {
        return _deployAndExecute(account, account, tokenIn, data);
    }

    function delegateDeploy(address account, address signer) external returns (address clone) {
        return _deploy(account, signer);
    }

    function delegateDeployAndExecute(
        address account,
        address signer,
        Token calldata tokenIn,
        bytes calldata data
    )
        external
        payable
        returns (address clone)
    {
        return _deployAndExecute(account, signer, tokenIn, data);
    }

    function getAddress(address account) external view returns (address) {
        return _getAddress(account, account);
    }

    function getDelegateAddress(address account, address signer) external view returns (address) {
        return _getAddress(account, signer);
    }

    function _getAddress(address account, address signer) internal view returns (address) {
        bytes32 salt = _getSalt(account, signer);
        return implementation.predictDeterministicAddress(salt, address(this));
    }

    function _getSalt(address account, address signer) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, signer));
    }

    function _deploy(address account, address signer) private returns (address clone) {
        bytes32 salt = _getSalt(account, signer);
        address clonePredicted = implementation.predictDeterministicAddress(salt, address(this));
        if (clonePredicted.code.length > 0) {
            return clonePredicted;
        }
        clone = implementation.cloneDeterministic(salt);
        IERC4337CloneInitializer(clone).initialize(account, signer, entryPoint);
        emit CloneDeployed(clone, account, signer);
    }

    function _deployAndExecute(
        address account,
        address signer,
        Token calldata tokenIn,
        bytes calldata data
    )
        private
        returns (address clone)
    {
        bytes32 salt = _getSalt(account, signer);
        address clonePredicted = implementation.predictDeterministicAddress(salt, address(this));
        if (clonePredicted.code.length > 0) {
            revert AlreadyDeployed(); // factory cannot call EnsoReceiver if it's already deployed
        }
        clone = implementation.cloneDeterministic(salt);
        bool isNativeAsset = _transfer(tokenIn, clone);
        if (!isNativeAsset && msg.value != 0) revert WrongMsgValue(msg.value, 0);
        IERC4337CloneInitializer(clone).initializeAndExecuteShortcut{ value: msg.value }(
            account, signer, entryPoint, data
        );
        emit CloneDeployed(clone, account, signer);
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
            revert UnsupportedTokenType(tokenType);
        }
    }
}

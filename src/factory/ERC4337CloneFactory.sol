// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC4337CloneInitializer } from "./interfaces/IERC4337CloneInitializer.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract ERC4337CloneFactory is Ownable, Initializable {
    using LibClone for address;

    address public implementation;
    address public entryPoint;

    error ImplementationNotSet();
    error EntryPointNotSet();

    constructor(address owner_) Ownable(owner_) {
        // could set the implementation here, but its nice to have a deterministic deployment
        // if we upgrade the implementation down the road, we would still have to deploy with
        // the old one to get the same
    }

    modifier implementationSet() {
        if (implementation == address(0)) revert ImplementationNotSet();
        _;
    }

    modifier entryPointSet() {
        if (entryPoint == address(0)) revert EntryPointNotSet();
        _;
    }

    function initialize(address implementation_, address entryPoint_) external initializer {
        implementation = implementation_;
        entryPoint = entryPoint_;
    }

    // @audit does it deviate from specs?
    // https://eips.ethereum.org/EIPS/eip-4337#reputation-scoring-and-throttlingbanning-for-global-entities
    function deploy(address account) external implementationSet entryPointSet returns (address clone) {
        bytes32 salt = _getSalt(account, account);
        clone = implementation.cloneDeterministic(salt);
        IERC4337CloneInitializer(clone).initialize(account, account, entryPoint);
    }

    function delegateDeploy(
        address account,
        address signer
    )
        external
        implementationSet
        entryPointSet
        returns (address clone)
    {
        bytes32 salt = _getSalt(account, signer);
        clone = implementation.cloneDeterministic(salt);
        IERC4337CloneInitializer(clone).initialize(account, signer, entryPoint);
    }

    // @audit trust conflicts. Factory owner can rug by changing the implementation
    function setImplementation(address newImplementation) external onlyOwner {
        implementation = newImplementation;
    }

    function setEntryPoint(address newEntryPoint) external onlyOwner {
        entryPoint = newEntryPoint;
    }

    function getAddress(address account) external view returns (address) {
        return _getAddress(account, account);
    }

    function getDelegateAddress(address account, address signer) external view returns (address) {
        return _getAddress(account, signer);
    }

    function _getAddress(address account, address signer) internal view implementationSet returns (address) {
        bytes32 salt = _getSalt(account, signer);
        return implementation.predictDeterministicAddress(salt, address(this));
    }

    function _getSalt(address account, address signer) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, signer));
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC4337CloneInitializer } from "./interfaces/IERC4337CloneInitializer.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract ERC4337CloneFactory {
    using LibClone for address;

    address public immutable implementation;
    address public immutable entryPoint;

    event CloneDeployed(address clone, address account, address signer);

    constructor(address implementation_, address entryPoint_) {
        implementation = implementation_;
        entryPoint = entryPoint_;
    }

    function deploy(address account) external returns (address clone) {
        bytes32 salt = _getSalt(account, account);
        clone = implementation.cloneDeterministic(salt);
        IERC4337CloneInitializer(clone).initialize(account, account, entryPoint);
        emit CloneDeployed(clone, account, account);
    }

    function delegateDeploy(address account, address signer) external returns (address clone) {
        bytes32 salt = _getSalt(account, signer);
        clone = implementation.cloneDeterministic(salt);
        IERC4337CloneInitializer(clone).initialize(account, signer, entryPoint);
        emit CloneDeployed(clone, account, signer);
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
}

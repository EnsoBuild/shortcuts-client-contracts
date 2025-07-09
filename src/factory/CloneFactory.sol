// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { LibClone } from "solady/utils/LibClone.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract CloneFactory is Ownable {
    using LibClone for address;

    error ImplementationNotSet();

    address public implementation;

    constructor(address owner_) Ownable(owner_) {
        // could set the implementation here, but its nice to have a deterministic deployment
        // if we upgrade the implementation down the road, we would still have to deploy with 
        // the old one to get the same
    }

    function setImplementation(address impl) external onlyOwner {
        implementation = impl;
    }

    function getAddress(address account) external view {
        if (implementation == address(0)) revert ImplementationNotSet();
        bytes32 salt = bytes32(uint256(uint160(account)));
        implementation.predictDeterministicAddress(salt, address(this));
    }
}
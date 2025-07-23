// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { ERC4337CloneFactory } from "../../src/factory/ERC4337CloneFactory.sol";

library PackedUserOperationLib {
    function generateInitCode(
        ERC4337CloneFactory accountFactory,
        address signer
    )
        internal
        pure
        returns (bytes memory initCode)
    {
        bytes memory initCalldata = abi.encodeWithSelector(accountFactory.deploy.selector, signer);
        initCode = abi.encodePacked(address(accountFactory), initCalldata);
    }

    function calculateGasFees() internal view returns (bytes32 gasFees_) {
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = uint128(block.basefee) + maxPriorityFeePerGas;
        gasFees_ = bytes32((uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas));
    }

    function calculateAccountGasLimits(
        uint256 shortcutTxGas,
        uint256 verificationGasLimit // verifcation gas limit includes deployment costs
    )
        internal
        pure
        returns (bytes32 accountGasLimits_)
    {
        accountGasLimits_ = bytes32(uint256(verificationGasLimit) << 128 | uint256(shortcutTxGas));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

contract TestPaymaster is IPaymaster {
    IEntryPoint public entryPoint;

    constructor(IEntryPoint entryPoint_) {
        entryPoint = entryPoint_;
    }

    function validatePaymasterUserOp(
        PackedUserOperation calldata, // userOp
        bytes32, // userOpHash
        uint256 // maxCost
    )
        external
        pure
        returns (bytes memory context, uint256 validationData)
    {
        // allow all
        return ("", 0);
    }

    function postOp(
        PostOpMode, // mode
        bytes calldata, // context
        uint256, // actualGasCost
        uint256 // actualUserOpFeePerGas
    )
        external
    {
        // allow all
    }

    function addDeposit() public payable {
        entryPoint.depositTo{ value: msg.value }(address(this));
    }
}

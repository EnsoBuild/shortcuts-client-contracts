// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IEntryPoint, PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { Test, Vm } from "forge-std/Test.sol";

abstract contract EntryPointAssertions is Test {
    function assertUserOperationCharge(
        Vm.Log[] memory logs,
        IEntryPoint entryPoint,
        PackedUserOperation memory userOp,
        address paymaster
    )
        internal
        view
        returns (uint256 actualGasCost)
    {
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        uint256 matches;
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (
                entry.emitter != address(entryPoint) || entry.topics.length == 0
                    || entry.topics[0] != IEntryPoint.UserOperationEvent.selector
            ) {
                continue;
            }
            assertEq(entry.topics.length, 4);
            assertEq(entry.topics[1], userOpHash);
            assertEq(entry.topics[2], bytes32(uint256(uint160(userOp.sender))));
            assertEq(entry.topics[3], bytes32(uint256(uint160(paymaster))));
            (uint256 nonce, bool success, uint256 gasCost, uint256 gasUsed) =
                abi.decode(entry.data, (uint256, bool, uint256, uint256));
            assertEq(nonce, userOp.nonce);
            assertTrue(success, "UserOperation failed");
            assertGt(gasCost, 0);
            assertGt(gasUsed, 0);
            uint256 maxFeePerGas = uint128(uint256(userOp.gasFees));
            assertLe(gasCost, gasUsed * maxFeePerGas, "Charge exceeds signed gas price");
            actualGasCost = gasCost;
            ++matches;
        }
        assertEq(matches, 1, "Expected exactly one UserOperationEvent");
    }
}

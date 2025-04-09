// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BaseSolver } from "./BaseSolver.sol";

contract BebopSolver is BaseSolver {
    address public immutable relayer;

    // @dev Constructor for the `BebopSolver` contract.
    // @param _owner The address of the owner who will be assigned the `OWNER_ROLE`. This parameter cannot be null.
    // @param _executor The address of the executor contract that interacts with this contract.
    // @param _relayer The address of the relayer responsible for submitting transactions.
    constructor(address _owner, address _executor, address _relayer) BaseSolver(_owner, _executor) {
        if (_relayer == address(0)) {
            revert NotPermitted();
        }
        relayer = _relayer;
    }

    // @notice Executes a series of pre-encoded commands (shortcuts) on behalf of a solver.
    // @param accountId The bytes32 value representing an API user
    // @param requestId The bytes32 value representing an API request
    // @param commands An array of bytes32 values that encode calls
    // @param state An array of bytes that are used to generate call data for each command
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        public
        payable
        override
        returns (bytes[] memory)
    {
        if (relayer != tx.origin) {
            revert NotPermitted();
        }
        return super.executeShortcut(accountId, requestId, commands, state);
    }
}

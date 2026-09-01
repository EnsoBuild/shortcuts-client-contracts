// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Ownable, Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";

struct Call {
    address target;
    bool required;
    bytes data;
}

struct Result {
    bool success;
    bytes returnData;
}

/// @title KeeperWallet
/// @author Enso
/// @notice Simple wallet that executes single or batched calls, restricted to the owner and approved executors
contract KeeperWallet is Ownable2Step {
    /// @notice Accounts authorized to execute calls through this wallet
    mapping(address executor => bool isAllowed) public executors;

    /// @notice Emitted when an executor is added or removed
    /// @param executor The address of the executor
    /// @param allowed Whether the executor is allowed to execute calls
    event ExecutorSet(address indexed executor, bool allowed);

    /// @notice Thrown when the sender is neither the owner nor an approved executor
    /// @param sender The address that attempted the unauthorized call
    error KeeperWallet_InvalidSender(address sender);

    /// @notice Thrown when a call fails without a revert reason
    error KeeperWallet_ExecutionFailedNoReason();

    /// @dev The owner is always allowed to execute, so funds can be moved out even with no executors set
    modifier onlyExecutor() {
        if (msg.sender != owner() && !executors[msg.sender]) {
            revert KeeperWallet_InvalidSender(msg.sender);
        }
        _;
    }

    constructor(address owner_) Ownable(owner_) { }

    receive() external payable { }

    /// @notice Executes a single call
    /// @param target The address of the contract to call
    /// @param value The amount of native token to send with the call
    /// @param data The calldata to send to the target contract
    /// @return response The return data of the call
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        payable
        onlyExecutor
        returns (bytes memory response)
    {
        bool success;
        (success, response) = target.call{ value: value }(data);
        if (!success) {
            _revertWith(response);
        }
    }

    /// @notice Executes multiple calls, reverting all only if a required call fails
    /// @param calls The calls to execute
    /// @return results The success flag and return data of each call
    function executeMulti(Call[] calldata calls) external onlyExecutor returns (Result[] memory results) {
        results = new Result[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            Call calldata call = calls[i];
            (bool success, bytes memory returnData) = call.target.call(call.data);
            if (!success && call.required) {
                _revertWith(returnData);
            }
            results[i] = Result({ success: success, returnData: returnData });
        }
    }

    /// @notice Authorizes or deauthorizes an address to execute calls
    /// @param executor The address to authorize or deauthorize
    /// @param allowed Whether the address should be allowed
    function setExecutor(address executor, bool allowed) external onlyOwner {
        executors[executor] = allowed;
        emit ExecutorSet(executor, allowed);
    }

    function _revertWith(bytes memory response) private pure {
        if (response.length > 0) {
            assembly ("memory-safe") {
                revert(add(0x20, response), mload(response))
            }
        }
        revert KeeperWallet_ExecutionFailedNoReason();
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { Withdrawable } from "../utils/Withdrawable.sol";

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

contract EnsoWalletV2 is AbstractMultiSend, AbstractEnsoShortcuts, Initializable, Withdrawable {
    string public constant VERSION = "1.0.0";
    address public factory;
    address private _owner;

    error InvalidSender(address sender);

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @notice Initializes the wallet with an owner address
     * @param owner_ The address that will own this wallet
     */
    function initialize(address owner_) external initializer {
        _owner = owner_;
        // sender has to be the factory
        factory = msg.sender;
    }

    /**
     * @notice Executes an arbitrary call to a target contract
     * @param target The address of the contract to call
     * @param value The amount of native token to send with the call
     * @param data The calldata to send to the target contract
     * @return success Whether the call succeeded
     */
    function execute(
        address target,
        uint256 value,
        bytes memory data
    )
        external
        payable
        onlyOwner
        returns (bool success)
    {
        assembly {
            success := call(gas(), target, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /**
     * @notice Executes a shortcut
     * @dev Can be called by owner or factory
     * @param accountId The bytes32 value representing an API user
     * @param requestId The bytes32 value representing an API request
     * @param commands An array of bytes32 values that encode calls
     * @param state An array of bytes that are used to generate call data for each command
     * @return response Array of response data from each executed command
     */
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        public
        payable
        override
        returns (bytes[] memory response)
    {
        return super.executeShortcut(accountId, requestId, commands, state);
    }

    /// @notice Abstract override function to return owner
    function owner() public view override returns (address) {
        return _owner;
    }

    /// @notice Abstract override function to validate msg.sender
    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        if (msg.sender != factory && msg.sender != owner()) revert InvalidSender(msg.sender);
    }

    /// @notice Abstract override function to validate if sender is the owner
    function _checkOwner() internal view override {
        if (msg.sender != owner()) revert InvalidSender(msg.sender);
    }
}

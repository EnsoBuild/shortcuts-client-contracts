// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { Withdrawable } from "../utils/Withdrawable.sol";
import { IEnsoWalletV2 } from "./interfaces/IEnsoWalletV2.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

contract EnsoWalletV2 is IEnsoWalletV2, AbstractMultiSend, AbstractEnsoShortcuts, Initializable, Withdrawable {
    string public constant VERSION = "1.0.0";
    address public factory;
    address private _owner;

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
        (bool success, bytes memory response) = target.call{ value: msg.value }(data);
        if (!success) {
            if (response.length > 0) {
                assembly ("memory-safe") {
                    revert(add(0x20, response), mload(response))
                }
            }
            revert ExecutionFailed();
        }
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

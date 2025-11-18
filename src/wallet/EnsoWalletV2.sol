// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { Withdrawable } from "../utils/Withdrawable.sol";
import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

/// @title EnsoWalletV2
/// @author Enso
/// @notice Minimal wallet that supports shortcuts, multi-send, and arbitrary execution
contract EnsoWalletV2 is IEnsoWalletV2, AbstractMultiSend, AbstractEnsoShortcuts, Initializable, Withdrawable {
    /// @inheritdoc IEnsoWalletV2
    string public constant VERSION = "1.0.0";
    address public factory;
    address private _owner;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @inheritdoc IEnsoWalletV2
    function initialize(address owner_) external initializer {
        _owner = owner_;
        factory = msg.sender;
    }

    /// @inheritdoc IEnsoWalletV2
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
        bytes memory response;
        (success, response) = target.call{ value: value }(data);
        if (!success) {
            if (response.length > 0) {
                assembly ("memory-safe") {
                    revert(add(0x20, response), mload(response))
                }
            }
            revert EnsoWalletV2_ExecutionFailed();
        }
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        if (msg.sender != factory && msg.sender != owner()) {
            revert EnsoWalletV2_InvalidSender(msg.sender);
        }
    }

    function _checkOwner() internal view override {
        if (msg.sender != owner()) {
            revert EnsoWalletV2_InvalidSender(msg.sender);
        }
    }
}

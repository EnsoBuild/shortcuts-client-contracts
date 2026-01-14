// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { AbstractMultiSend } from "../AbstractMultiSend.sol";
import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { Withdrawable } from "../utils/Withdrawable.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

/// @title EnsoWalletV2
/// @author Enso
/// @notice Minimal wallet that supports shortcuts, multi-send, and arbitrary execution
contract EnsoWalletV2 is IEnsoWalletV2, AbstractMultiSend, AbstractEnsoShortcuts, Initializable, Withdrawable {
    /// @inheritdoc IEnsoWalletV2
    string public constant VERSION = "1.0.1";
    address public factory;
    address private _owner;

    /// @inheritdoc IEnsoWalletV2
    mapping(address executor => bool isAllowed) public executors;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor() {
        _disableInitializers();
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
            revert EnsoWalletV2_ExecutionFailedNoReason();
        }
    }

    /// @inheritdoc IEnsoWalletV2
    function setExecutor(address executor, bool allowed) external onlyOwner {
        executors[executor] = allowed;
        emit ExecutorSet(executor, allowed);
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    function _checkMsgSender() internal view override(AbstractEnsoShortcuts, AbstractMultiSend) {
        if (msg.sender != owner() && msg.sender != factory && !executors[msg.sender]) {
            revert EnsoWalletV2_InvalidSender(msg.sender);
        }
    }

    /// @inheritdoc IEnsoWalletV2
    /// @dev Explicit override required because executeShortcut is defined in both
    ///      IEnsoWalletV2 and AbstractEnsoShortcuts
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        public
        payable
        override(IEnsoWalletV2, AbstractEnsoShortcuts)
        returns (bytes[] memory response)
    {
        return super.executeShortcut(accountId, requestId, commands, state);
    }

    function _checkOwner() internal view override {
        if (msg.sender != owner()) {
            revert EnsoWalletV2_InvalidSender(msg.sender);
        }
    }
}

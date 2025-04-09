// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../AbstractEnsoShortcuts.sol";
import { MinimalWallet } from "./MinimalWallet.sol";

contract BaseSolver is AbstractEnsoShortcuts, MinimalWallet {
    address public immutable executor;

    // @dev Constructor for the `BaseSolver` contract.
    // @param _owner The address of the owner who will be assigned the `OWNER_ROLE`. This parameter cannot be null.
    // @param _executor The address of the executor contract that interacts with this contract.
    constructor(address _owner, address _executor) MinimalWallet(_owner) {
        if (_executor == address(0)) {
            revert NotPermitted();
        }
        executor = _executor;
    }

    function _checkMsgSender() internal view override {
        if (msg.sender != executor) revert NotPermitted();
    }

    receive() external payable override(AbstractEnsoShortcuts, MinimalWallet) { }
}

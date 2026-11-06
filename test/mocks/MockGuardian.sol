// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../src/interfaces/IEnsoRouter.sol";
import { IIntentGuardian, Level, Obligation, Status } from "../../src/interfaces/IIntentGuardian.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// A FORWARD-style guardian that pulls exactly the handed amount and records the obligation.
contract MockGuardian is IIntentGuardian {
    Level public level;
    bytes32 public lastIntentHash;
    uint256 public lastAmount;
    uint256 public lastValue;
    bytes public lastContext;
    Obligation private s_last;
    uint256 public accepts;

    constructor(Level level_) {
        level = level_;
    }

    receive() external payable { }

    function setLevel(Level level_) external {
        level = level_;
    }

    function accept(
        bytes32 intentHash,
        Token calldata token,
        uint256 amount,
        Obligation calldata obligation,
        bytes calldata context
    )
        external
        payable
        returns (bytes32 receipt)
    {
        if (token.tokenType == TokenType.ERC20) {
            (address erc20,) = abi.decode(token.data, (address, uint256));
            IERC20(erc20).transferFrom(msg.sender, address(this), amount);
        }
        ++accepts;
        lastIntentHash = intentHash;
        lastAmount = amount;
        lastValue = msg.value;
        lastContext = context;
        s_last = obligation;
        receipt = keccak256(abi.encode(intentHash, accepts));
        emit Accepted(receipt, intentHash, tx.origin, obligation);
    }

    function lastObligation() external view returns (Obligation memory) {
        return s_last;
    }

    function settle(bytes32, Status, bytes calldata) external pure {
        revert("unsupported");
    }

    function status(bytes32) external pure returns (Status) {
        return Status.PENDING;
    }
}

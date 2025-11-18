// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { TokenType } from "../interfaces/IEnsoRouter.sol";

interface IEnsoWalletV2Factory {
    event EnsoWalletV2Deployed(address wallet, address indexed account);

    error ExecutionFailed();
    error UnsupportedTokenType(TokenType tokenType);
    error WrongMsgValue(uint256 value, uint256 expectedAmount);

    function deploy(address account) external returns (address wallet);

    function deployAndExecute(
        Token calldata tokenIn,
        bytes calldata data
    )
        external
        payable
        returns (address wallet, bytes memory response);

    function getAddress(address account) external view returns (address);
}


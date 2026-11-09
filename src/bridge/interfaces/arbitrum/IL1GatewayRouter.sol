// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

/// @title IL1GatewayRouter
/// @notice The part of Arbitrum's L1 gateway router that EnsoArbitrumDepositor uses
interface IL1GatewayRouter {
    function getGateway(address token) external view returns (address gateway);

    function outboundTransferCustomRefund(
        address token,
        address refundTo,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory);
}

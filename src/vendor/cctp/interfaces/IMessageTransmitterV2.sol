// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

interface IMessageTransmitterV2 {
    function localDomain() external view returns (uint32);

    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);

    function version() external view returns (uint32);
}

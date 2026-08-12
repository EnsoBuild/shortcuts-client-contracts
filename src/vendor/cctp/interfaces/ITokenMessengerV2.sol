// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

interface ITokenMinterV2 {
    function getLocalToken(uint32 remoteDomain, bytes32 remoteToken) external view returns (address);
}

interface ITokenMessengerV2 {
    function localMinter() external view returns (ITokenMinterV2);
}

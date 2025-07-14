// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenMessaging {
    function assetIds(address) external view returns (uint16);
}

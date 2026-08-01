// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDeepstateV1 {
    struct FillParams {
        address token0;
        address token1;
        uint256 epoch;
        bytes32 order;
        bool isBid;
        bool noRest;
        bool fillOrKill;
    }

    function fillRoute(FillParams[] calldata fills) external payable;
}

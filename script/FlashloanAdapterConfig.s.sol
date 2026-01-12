// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/flashloan/AbstractEnsoFlashloan.sol";

abstract contract FlashloanAdapterConfig {
    uint256 constant ETHEREUM = 1;
    uint256 constant BERACHAIN = 80_094;

    mapping(uint256 chainId => address[] lenders) internal _lenders;
    mapping(uint256 chainId => LenderProtocol[] protocols) internal _protocols;
    mapping(uint256 chainId => address shortcuts) internal _shortcuts;

    function _initConfigs() internal {
        //
        // Ethereum
        //
        _lenders[ETHEREUM].push(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // Aave V3
        _protocols[ETHEREUM].push(LenderProtocol.AaveV3);

        _lenders[ETHEREUM].push(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho
        _protocols[ETHEREUM].push(LenderProtocol.Morpho);

        _lenders[ETHEREUM].push(0xbA1333333333a1BA1108E8412f11850A5C319bA9); // Balancer V3
        _protocols[ETHEREUM].push(LenderProtocol.BalancerV3);

        _lenders[ETHEREUM].push(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072); // Dolomite
        _protocols[ETHEREUM].push(LenderProtocol.Dolomite);

        _shortcuts[ETHEREUM] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts

        //
        // Berachain
        //
        _lenders[BERACHAIN].push(0x24147243f9c08d835C218Cda1e135f8dFD0517D0); // Bend (Morpho fork)
        _protocols[BERACHAIN].push(LenderProtocol.Morpho);

        _lenders[BERACHAIN].push(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D); // Dolomite
        _protocols[BERACHAIN].push(LenderProtocol.Dolomite);

        _shortcuts[BERACHAIN] = 0xA2F4f9C6ec598CA8c633024f8851c79CA5F43e48; // DelegateEnsoShortcuts
    }
}

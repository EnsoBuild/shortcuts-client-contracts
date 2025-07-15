// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";

// Deployer for the Wayfinder FeeSplitter
contract FeeSplitterDeployerWayfinder is Script {
    mapping(uint256 chainId => address feeCollector) private chainIdToEnsoFeeCollector;
    mapping(uint256 chainId => address feeCollector) private chainIdToPartnerFeeCollector;

    constructor() {
        chainIdToEnsoFeeCollector[ChainId.ETHEREUM] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.BINANCE] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.POLYGON] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.HYPER] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.BASE] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.ARBITRUM] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.AVALANCHE] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;

        chainIdToPartnerFeeCollector[ChainId.ETHEREUM] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.BINANCE] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.POLYGON] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.HYPER] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.BASE] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.ARBITRUM] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
        chainIdToPartnerFeeCollector[ChainId.AVALANCHE] = 0xBfC330020E3267Cea008718f1712f1dA7F0d32A9;
    }

    function run() public returns (address feeSplitter, address ensoFeeCollector, address partnerFeeCollector) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;

        ensoFeeCollector = chainIdToEnsoFeeCollector[chainId];
        partnerFeeCollector = chainIdToPartnerFeeCollector[chainId];
        if (ensoFeeCollector == address(0)) revert();
        if (partnerFeeCollector == address(0)) revert();

        address[] memory recipients = new address[](2);
        recipients[0] = partnerFeeCollector;
        recipients[1] = ensoFeeCollector;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 7;
        shares[1] = 3;

        vm.broadcast(deployerPrivateKey);
        feeSplitter = address(new FeeSplitter(ensoFeeCollector, recipients, shares));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";

// Deployer for the Infrared FeeSplitter
contract FeeSplitterDeployerEtherFi is Script {
    mapping(uint256 chainId => address feeCollector) private chainIdToEnsoFeeCollector;
    mapping(uint256 chainId => address feeCollector) private chainIdToPartnerFeeCollector;

    constructor() {
        chainIdToEnsoFeeCollector[ChainId.ETHEREUM] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.BASE] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.ARBITRUM] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.LINEA] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        chainIdToEnsoFeeCollector[ChainId.BERACHAIN] = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;

        chainIdToPartnerFeeCollector[ChainId.ETHEREUM] = 0x46Cba1e9B1e5Db32dA28428f2fb85587BCb785E7;
        chainIdToPartnerFeeCollector[ChainId.BASE] = 0x46Cba1e9B1e5Db32dA28428f2fb85587BCb785E7;
        chainIdToPartnerFeeCollector[ChainId.ARBITRUM] = 0x46Cba1e9B1e5Db32dA28428f2fb85587BCb785E7;
        chainIdToPartnerFeeCollector[ChainId.LINEA] = 0x46Cba1e9B1e5Db32dA28428f2fb85587BCb785E7;
        chainIdToPartnerFeeCollector[ChainId.BERACHAIN] = 0x46Cba1e9B1e5Db32dA28428f2fb85587BCb785E7;
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
        shares[0] = 1;
        shares[1] = 1;

        vm.broadcast(deployerPrivateKey);
        feeSplitter = address(new FeeSplitter(ensoFeeCollector, recipients, shares));
    }
}

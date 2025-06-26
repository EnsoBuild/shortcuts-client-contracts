// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";

contract FeeSplitterDeployerBerapaw is Script {
    mapping(uint256 chainId => address feeCollector) private chainIdToEnsoFeeCollector;
    mapping(uint256 chainId => address feeCollector) private chainIdToPartnerFeeCollector;

    constructor() {
        chainIdToEnsoFeeCollector[ChainId.BERACHAIN] = 0xA67B61399B8b817e763f05dEF4694F22f1bDCC7d;

        chainIdToPartnerFeeCollector[ChainId.BERACHAIN] = 0xD77e8C1024DE383f5bedcAfBaFa3d0Ab5369C70A;
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/helpers/UniswapV4Helpers.sol";

contract FullDeployer is Script {
    function run() public returns (UniswapV4Helpers uniswapV4Helpers, address poolManager) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        uint256 chainId = block.chainid;

        if (chainId == 1) {
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else if (chainId == 10) {
            poolManager = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
        } else if (chainId == 130) {
            poolManager = 0x1F98400000000000000000000000000000000004;
        } else if (chainId == 137) {
            poolManager = 0x67366782805870060151383F4BbFF9daB53e5cD6;
        } else if (chainId == 8543) {
            poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        } else if (chainId == 42161) {
            poolManager = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
        } else {
            revert("No pool manager");
        }

        uniswapV4Helpers = new UniswapV4Helpers{salt: "UniswapV4Helpers"}(poolManager);

        vm.stopBroadcast();
    }
}

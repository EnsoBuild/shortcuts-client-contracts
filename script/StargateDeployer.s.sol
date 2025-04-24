// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/bridge/StargateV2Receiver.sol";
import "forge-std/Script.sol";

contract StargateDeployer is Script {
    function run() public returns (address stargateHelper, address endpoint) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        uint256 chainId = block.chainid;

        if (chainId == 324) {
            endpoint = 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF; // zksync
        } else if (chainId == 130 || chainId == 146 || chainId == 480 || chainId == 80_094) {
            endpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B; // unichain, sonic, worldchain, berachain
        } else if (chainId == 57_073) {
            endpoint = 0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958; // ink
        } else if (chainId == 1868) {
            endpoint = 0x4bCb6A963a9563C33569D7A512D35754221F3A19; // soneium
        } else if (chainId == 999) {
            endpoint = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9; // hyper
        } else {
            endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // default
        }

        stargateHelper = address(new StargateV2Receiver{ salt: "StargateV2Receiver" }(endpoint));

        vm.stopBroadcast();
    }
}

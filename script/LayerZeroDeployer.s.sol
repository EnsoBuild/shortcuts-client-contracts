// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/bridge/LayerZeroReceiver.sol";
import "../src/libraries/DataTypes.sol";
import "forge-std/Script.sol";

contract LayerZeroDeployer is Script {
    function run() public returns (address lzReceiver, address endpoint, address router) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA;
        uint256 chainId = block.chainid;
        if (chainId == ChainId.ZKSYNC) {
            endpoint = 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF; // zksync
            router = 0x1BD8CefD703CF6b8fF886AD2E32653C32bc62b5C;
        } else if (
            chainId == ChainId.UNICHAIN || chainId == ChainId.SONIC || chainId == ChainId.WORLD
                || chainId == ChainId.BERACHAIN
        ) {
            endpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B; // unichain, sonic, worldchain, berachain
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.KATANA) {
            endpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B; // katana
            router = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F;
        } else if (chainId == ChainId.INK) {
            endpoint = 0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958; // ink
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.SONEIUM) {
            endpoint = 0x4bCb6A963a9563C33569D7A512D35754221F3A19; // soneium
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.HYPER) {
            endpoint = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9; // hyper
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.LINEA) {
            endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // linea
            router = 0xA146d46823f3F594B785200102Be5385CAfCE9B5;
        } else if (chainId == ChainId.PLUME) {
            endpoint = 0xC1b15d3B262bEeC0e3565C11C9e0F6134BdaCB36; // plume
            router = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F;
        } else {
            endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // default
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        }

        lzReceiver = address(new LayerZeroReceiver{ salt: "LayerZeroReceiver" }(endpoint, router, deployer, 100_000));

        vm.stopBroadcast();
    }
}

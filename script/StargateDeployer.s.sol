// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/bridge/StargateV2Receiver.sol";
import "forge-std/Script.sol";

contract StargateDeployer is Script {
    mapping(uint256 => address) private tokenMessagingAddresses;

    constructor() {
        tokenMessagingAddresses[1] = 0x6d6620eFa72948C5f68A3C8646d58C00d3f4A980; //ethereum
        tokenMessagingAddresses[10] = 0xF1fCb4CBd57B67d683972A59B6a7b1e2E8Bf27E6; //optimism
        tokenMessagingAddresses[56] = 0x6E3d884C96d640526F273C61dfcF08915eBd7e2B; //binance
        tokenMessagingAddresses[100] = 0xAf368c91793CB22739386DFCbBb2F1A9e4bCBeBf; //gnosis
        tokenMessagingAddresses[130] = 0xB1EeAD6959cb5bB9B20417d6689922523B2B86C3; //unichain
        tokenMessagingAddresses[137] = 0x6CE9bf8CDaB780416AD1fd87b318A077D2f50EaC; //polygon
        tokenMessagingAddresses[146] = 0x2086f755A6d9254045C257ea3d382ef854849B0f; //sonic
        tokenMessagingAddresses[1868] = 0xAF54BE5B6eEc24d6BFACf1cce4eaF680A8239398; //soneium
        tokenMessagingAddresses[8453] = 0x5634c4a5FEd09819E3c46D86A965Dd9447d86e47; //base
        tokenMessagingAddresses[42_161] = 0x19cFCE47eD54a88614648DC3f19A5980097007dD; //arbitrum
        tokenMessagingAddresses[43_114] = 0x17E450Be3Ba9557F2378E20d64AD417E59Ef9A34; //avalanche
        tokenMessagingAddresses[57_073] = 0x45f1A95A4D3f3836523F5c83673c797f4d4d263B; //ink
        tokenMessagingAddresses[59_144] = 0x5f688F563Dc16590e570f97b542FA87931AF2feD; //linea
        tokenMessagingAddresses[80_094] = 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6; //bera
        tokenMessagingAddresses[98_866] = 0xf26d57bbE1D99561B13003783b5e040B71AdCb14; //plume
    }

    function run() public returns (address stargateHelper, address endpoint, address tokenMessaging, address router) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA;
        uint256 chainId = block.chainid;

        tokenMessaging = tokenMessagingAddresses[chainId];
        if (tokenMessaging == address(0)) revert();
        if (chainId == 324) {
            endpoint = 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF; // zksync
            router = 0x1BD8CefD703CF6b8fF886AD2E32653C32bc62b5C;
        } else if (chainId == 130 || chainId == 146 || chainId == 480 || chainId == 80_094) {
            endpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B; // unichain, sonic, worldchain, berachain
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == 57_073) {
            endpoint = 0xca29f3A6f966Cb2fc0dE625F8f325c0C46dbE958; // ink
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == 1868) {
            endpoint = 0x4bCb6A963a9563C33569D7A512D35754221F3A19; // soneium
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == 999) {
            endpoint = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9; // hyper
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == 59_144) {
            endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // linea
            router = 0xA146d46823f3F594B785200102Be5385CAfCE9B5;
        } else if (chainId == 98_866) {
            endpoint = 0xC1b15d3B262bEeC0e3565C11C9e0F6134BdaCB36; // plume
            router = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F;
        } else {
            endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // default
            router = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        }

        stargateHelper = address(
            new StargateV2Receiver{ salt: "StargateV2Receiver" }(endpoint, router, deployer, 100_000)
        );

        vm.stopBroadcast();
    }
}

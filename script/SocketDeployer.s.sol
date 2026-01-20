// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { EnsoShortcuts } from "../src/EnsoShortcuts.sol";
import { Script } from "forge-std/Script.sol";

contract Deployer is Script {
    mapping(uint256 => address) socketReceivers;

    constructor() {
        // Ethereum
        socketReceivers[1] = 0x362c116779D2d27F822a497E4650B6e2616d3859;

        // Optimism
        socketReceivers[10] = 0xddC3A2bc1D6252D09A82814269d602D84Ca3E7ae;

        // BNB Chain
        socketReceivers[56] = 0x71cF3E64E42bcAEC7485AF71571d7033E5b7dF93;

        // Polygon
        socketReceivers[137] = 0x8DfeB2e0B392f0033C8685E35FB4763d88a70d12;

        // Arbitrum
        socketReceivers[42_161] = 0x88616cB9499F32Ff6A784B66B60aABF0bCf0df39;

        // Avalanche
        socketReceivers[43_114] = 0x83b2cda6A33128324ee9cb2f0360bA8a42Cec2C6;
    }

    function run() public returns (EnsoShortcuts socketEnsoShortcuts) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address socketReceiver = socketReceivers[block.chainid];

        vm.broadcast(deployerPrivateKey);
        socketEnsoShortcuts = new EnsoShortcuts{ salt: "SocketEnsoShortcuts" }(socketReceiver);
    }
}

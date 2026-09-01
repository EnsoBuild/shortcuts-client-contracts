// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ChainOwner } from "../src/libraries/ChainOwner.sol";
import { KeeperWallet } from "../src/wallet/KeeperWallet.sol";
import { Script } from "forge-std/Script.sol";

contract KeeperWalletDeployer is Script {
    /// @notice Executors to authorize on the wallet right after deployment.
    function _executors() internal pure returns (address[] memory executors) {
        executors = new address[](2);
        executors[0] = 0xBC33367eede0e3d0724A075393A0E33f09a5119b;
        executors[1] = 0x030F2C58d064AD0ee5ff59C625b81e4Eb5c97944;
    }

    function run() public returns (KeeperWallet wallet, address owner) {
        owner = ChainOwner.ownerFor(block.chainid);
        address[] memory executors = _executors();

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        // The deployer owns the wallet initially so it can authorize the executors,
        // since setExecutor is onlyOwner.
        wallet = new KeeperWallet{ salt: "KeeperWallet" }(deployer);

        for (uint256 i; i < executors.length; ++i) {
            wallet.setExecutor(executors[i], true);
        }

        // Two-step handoff: the chain owner must call acceptOwnership() to complete it.
        wallet.transferOwnership(owner);

        vm.stopBroadcast();
    }
}

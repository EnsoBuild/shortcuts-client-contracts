// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BebopSolver } from "../src/solvers/BebopSolver.sol";
import { Script } from "forge-std/Script.sol";

struct BebopSolverResult {
    BebopSolver shortcuts;
}

contract BebopSolverDeployer is Script {
    function run() public returns (BebopSolverResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.broadcast(deployerPrivateKey);
        result.shortcuts = new BebopSolver{ salt: "BebopSolver" }(
            vm.envAddress("OWNER"),
            0xbEbEbEb035351f58602E0C1C8B59ECBfF5d5f47b, // Bebop Jam Settlement
            vm.envAddress("RELAYER")
        );
    }
}

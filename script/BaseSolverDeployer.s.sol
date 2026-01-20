// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BaseSolver } from "../src/solvers/BaseSolver.sol";
import { Script } from "forge-std/Script.sol";

struct BaseSolverResult {
    BaseSolver shortcuts;
}

contract BaseSolverDeployer is Script {
    function run() public returns (BaseSolverResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.broadcast(deployerPrivateKey);
        result.shortcuts = new BaseSolver{ salt: "BaseSolver" }(vm.envAddress("OWNER"), vm.envAddress("EXECUTOR"));
    }
}

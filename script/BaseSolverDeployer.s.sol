// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/solvers/BaseSolver.sol";

struct BaseSolverResult {
    BaseSolver shortcuts;
}

contract BaseSolverDeployer is Script {
    function run() public returns (BaseSolverResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.broadcast(deployerPrivateKey);
        result.shortcuts = new BaseSolver{salt: "BaseSolver"}(
            vm.envAddress("OWNER"),
            vm.envAddress("EXECUTOR")
        );
    }
}

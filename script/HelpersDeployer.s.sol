// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/helpers/DecimalHelpers.sol";

import { ERC20Helpers } from "../src/helpers/ERC20Helpers.sol";
import "../src/helpers/EnsoShortcutsHelpers.sol";
import "../src/helpers/MathHelpers.sol";
import "../src/helpers/PercentageMathHelpers.sol";
import "../src/helpers/SignedMathHelpers.sol";
import { SwapHelpers } from "../src/helpers/SwapHelpers.sol";
import "../src/helpers/TupleHelpers.sol";
import "forge-std/Script.sol";

struct DeployerResult {
    DecimalHelpers decimalHelpers;
    EnsoShortcutsHelpers shortcutsHelpers;
    ERC20Helpers erc20Helpers;
    MathHelpers mathHelpers;
    PercentageMathHelpers percentageMathHelpers;
    SignedMathHelpers signedMathHelpers;
    SwapHelpers swapHelpers;
    TupleHelpers tupleHelpers;
}

contract FullDeployer is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.decimalHelpers = new DecimalHelpers{ salt: "DecimalHelpers" }();
        result.shortcutsHelpers = new EnsoShortcutsHelpers{ salt: "EnsoShortcutsHelpers" }();
        result.erc20Helpers = new ERC20Helpers{ salt: "ERC20Helpers" }();
        result.mathHelpers = new MathHelpers{ salt: "MathHelpers" }();
        result.percentageMathHelpers = new PercentageMathHelpers{ salt: "PercentageMathHelpers" }();
        result.signedMathHelpers = new SignedMathHelpers{ salt: "SignedMathHelpers" }();
        result.swapHelpers = new SwapHelpers{ salt: "SwapHelpers" }();
        result.tupleHelpers = new TupleHelpers{ salt: "TupleHelpers" }();

        vm.stopBroadcast();
    }
}

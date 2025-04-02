// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/router/EnsoRouter.sol";
import "../src/delegate/DelegateEnsoShortcuts.sol";
import "../src/helpers/DecimalHelpers.sol";
import "../src/helpers/EnsoShortcutsHelpers.sol";
import {ERC20Helpers} from "../src/helpers/ERC20Helpers.sol";
import "../src/helpers/MathHelpers.sol";
import "../src/helpers/PercentageMathHelpers.sol";
import "../src/helpers/SignedMathHelpers.sol";
import {SwapHelpers} from "../src/helpers/SwapHelpers.sol";
import "../src/helpers/TupleHelpers.sol";

struct DeployerResult {
    EnsoRouter router;
    EnsoShortcuts shortcuts;
    DelegateEnsoShortcuts delegate;
    DecimalHelpers decimalHelpers;
    EnsoShortcutsHelpers shortcutsHelpers;
    ERC20Helpers erc20Helpers;
    MathHelpers mathHelpers;
    PercentageMathHelpers percentageMathHelpers;
    SignedMathHelpers signedMathHelpers;
    SwapHelpers swapHelpers;
    TupleHelpers tupleHelpers;
}

contract FullDeploy is Script {
    function run() public returns (DeployerResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        result.router = new EnsoRouter{salt: "EnsoRouter"}();
        result.shortcuts = result.router.enso();
        result.delegate = new DelegateEnsoShortcuts{salt: "DelegateEnsoShortcuts"}();

        result.decimalHelpers = new DecimalHelpers{salt: "DecimalHelpers"}();
        result.shortcutsHelpers = new EnsoShortcutsHelpers{salt: "EnsoShortcutsHelpers"}();
        result.erc20Helpers = new ERC20Helpers{salt: "ERC20Helpers"}();
        result.mathHelpers = new MathHelpers{salt: "MathHelpers"}();
        result.percentageMathHelpers = new PercentageMathHelpers{salt: "PercentageMathHelpers"}();
        result.signedMathHelpers = new SignedMathHelpers{salt: "SignedMathHelpers"}();
        result.swapHelpers = new SwapHelpers{salt: "SwapHelpers"}();
        result.tupleHelpers = new TupleHelpers{salt: "TupleHelpers"}();

        vm.stopBroadcast();
    }
}

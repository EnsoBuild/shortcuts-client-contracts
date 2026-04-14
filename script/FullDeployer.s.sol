// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../src/EnsoShortcuts.sol";
import { DelegateEnsoShortcuts } from "../src/delegate/DelegateEnsoShortcuts.sol";
import { EnsoWalletV2Factory } from "../src/factory/EnsoWalletV2Factory.sol";
import { DecimalHelpers } from "../src/helpers/DecimalHelpers.sol";
import { ERC20Helpers } from "../src/helpers/ERC20Helpers.sol";
import { EnsoShortcutsHelpers } from "../src/helpers/EnsoShortcutsHelpers.sol";
import { MathHelpers } from "../src/helpers/MathHelpers.sol";
import { PercentageMathHelpers } from "../src/helpers/PercentageMathHelpers.sol";
import { SignedMathHelpers } from "../src/helpers/SignedMathHelpers.sol";
import { SwapHelpers } from "../src/helpers/SwapHelpers.sol";
import { TupleHelpers } from "../src/helpers/TupleHelpers.sol";
import { EnsoRouter } from "../src/router/EnsoRouter.sol";
import { EnsoWalletV2 } from "../src/wallet/EnsoWalletV2.sol";
import { Script } from "forge-std/Script.sol";

struct DeployerResult {
    EnsoRouter router;
    EnsoShortcuts shortcuts;
    DelegateEnsoShortcuts delegate;
    EnsoWalletV2 wallet;
    EnsoWalletV2Factory walletFactory;
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

        result.router = new EnsoRouter{ salt: "EnsoRouter" }();
        result.shortcuts = EnsoShortcuts(payable(result.router.shortcuts()));
        result.delegate = new DelegateEnsoShortcuts{ salt: "DelegateEnsoShortcuts" }();
        result.wallet = new EnsoWalletV2{ salt: "EnsoWalletV2" }();
        result.walletFactory = new EnsoWalletV2Factory{ salt: "EnsoWalletV2Factory" }(address(result.wallet));

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

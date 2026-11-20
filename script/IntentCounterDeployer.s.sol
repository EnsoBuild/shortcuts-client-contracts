// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IntentCounter } from "../src/intent/IntentCounter.sol";
import { IntentDeployment } from "./IntentDeployment.sol";

/// Salted CREATE2 with no constructor arguments: one counter address on every chain.
contract IntentCounterDeployer is IntentDeployment {
    function run() public returns (IntentCounter counter) {
        _requireSupported();
        counter = IntentCounter(_deploy(COUNTER_SALT, type(IntentCounter).creationCode));
    }
}

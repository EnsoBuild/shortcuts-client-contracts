// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { IntentDeployment } from "./IntentDeployment.sol";

/// Salted CREATE2 with no constructor arguments: one factory address, and so one address per
/// intent tree, on every chain. The executor creation code the factory embeds links IntentEvaluator,
/// which forge deploys at its CREATE2 address first; see IntentDeployment.
contract EphemeralDeployer is IntentDeployment {
    function run() public returns (EphemeralFactory factory, address evaluator) {
        _requireSupported();
        bytes memory creationCode = type(EphemeralFactory).creationCode;
        evaluator = _requireLinked(creationCode, EVALUATOR);
        factory = EphemeralFactory(_deploy(FACTORY_SALT, creationCode));
    }
}

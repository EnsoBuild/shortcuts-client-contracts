// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IntentRouter } from "../src/router/IntentRouter.sol";
import { IntentDeployment } from "./IntentDeployment.sol";

/// Salted CREATE2. Routes run through the router each intent names, so the IntentRouter deploys no
/// EnsoShortcuts of its own. Links IntentHash and IntentEvaluator at their CREATE2 addresses, the
/// same IntentEvaluator the ephemeral factory links; see IntentDeployment.
contract IntentRouterDeployer is IntentDeployment {
    function run() public returns (IntentRouter router, address evaluator, address hash) {
        _requireSupported();
        bytes memory creationCode = type(IntentRouter).creationCode;
        evaluator = _requireLinked(creationCode, EVALUATOR);
        hash = _requireLinked(creationCode, HASH);
        router = IntentRouter(payable(_deploy(ROUTER_SALT, creationCode)));
    }
}

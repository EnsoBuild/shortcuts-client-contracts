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
        // The router shares the factory's intent lock, so the factory must be there first.
        require(_factory().code.length != 0, "deploy the ephemeral factory first");
        bytes memory creationCode = _routerCode();
        evaluator = _requireLinked(creationCode, EVALUATOR);
        hash = _requireLinked(creationCode, HASH);
        router = IntentRouter(payable(_deploy(ROUTER_SALT, creationCode)));
    }
}

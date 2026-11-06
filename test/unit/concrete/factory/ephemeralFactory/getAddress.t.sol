// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Intent } from "../../../../../src/interfaces/IIntent.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_GetAddress_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_MatchesTheDeployment() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        address predicted = s_factory.getAddress(root);
        _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);

        address executor = _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
        assertEq(executor, predicted, "deployed where predicted");
    }

    function test_DependsOnTheRootOnly() external view {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        intent.nonce = 1;
        assertTrue(
            s_factory.getAddress(root) != s_factory.getAddress(_root(intent)), "distinct roots, distinct addresses"
        );
    }
}

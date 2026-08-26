// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Intent } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_GetAddress_Unit_Concrete_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_WhenGivenATypedIntent() external view {
        Intent memory intent = _intent();

        // it should predict the executor CREATE2 address
        bytes32 initCodeHash = keccak256(abi.encodePacked(s_factory.executorCode(), abi.encode(intent)));
        address expected = computeCreate2Address(bytes32(0), initCodeHash, address(s_factory));
        assertEq(s_factory.getAddress(intent), expected);
    }

    function test_WhenAnyParameterChanges() external view {
        Intent memory intent = _intent();
        address original = s_factory.getAddress(intent);

        // it should derive a different address
        intent.nonce = 1;
        assertNotEq(s_factory.getAddress(intent), original);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralIntentExecutor } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_ExecutorCode_Unit_Concrete_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_ShouldReturnTheExecutorCreationCode() external view {
        // it should return the executor creation code
        assertEq(s_factory.executorCode(), type(EphemeralIntentExecutor).creationCode);
    }
}

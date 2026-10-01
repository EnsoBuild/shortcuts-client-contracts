// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_Constructor_Unit_Concrete_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_Constructor() external view {
        // it should set the router
        assertEq(s_factory.router(), address(s_router));
    }
}

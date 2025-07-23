// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract EnsoReceiver_Owner_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test {
    function test_ShouldReturnOwner() external view {
        // it should return owner
        assertEq(s_ensoReceiver.owner(), s_owner);
    }
}

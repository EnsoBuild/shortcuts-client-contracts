// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { SignaturePaymaster_Unit_Concrete_Test } from "./SignaturePaymaster.t.sol";
import { console2 } from "forge-std/Test.sol";

contract SignaturePaymaster_Version_Unit_Concrete_Test is SignaturePaymaster_Unit_Concrete_Test {
    function test_ShouldReturnVersion() external view {
        // it should return version
        assertEq(keccak256(bytes(s_signaturePaymaster.VERSION())) != keccak256(bytes("")), true);
    }
}

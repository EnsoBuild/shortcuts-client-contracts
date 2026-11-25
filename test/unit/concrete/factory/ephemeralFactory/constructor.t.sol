// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";

contract EphemeralFactory_Constructor_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_Domain() external view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            s_factory.eip712Domain();
        assertEq(name, "EphemeralFactory", "name");
        assertEq(version, "2", "version");
        assertEq(chainId, block.chainid, "chain");
        assertEq(verifyingContract, address(s_factory), "verifying contract");
    }

    function test_InitCodeTakesNoArguments() external pure {
        // The CREATE2 address depends on init code alone, so one salt gives one address everywhere.
        bytes memory code = type(EphemeralFactory).creationCode;
        assertGt(code.length, 0, "init code");
    }
}

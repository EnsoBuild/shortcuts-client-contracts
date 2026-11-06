// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";

contract IntentRouter_Constructor_Test is IntentRouter_Unit_Concrete_Test {
    function test_Domain() external view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            s_intentRouter.eip712Domain();
        assertEq(name, "IntentRouter", "name");
        assertEq(version, "2", "version");
        assertEq(chainId, block.chainid, "chain");
        assertEq(verifyingContract, address(s_intentRouter), "verifying contract");
    }
}

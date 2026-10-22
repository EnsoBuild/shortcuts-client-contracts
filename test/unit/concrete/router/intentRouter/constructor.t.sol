// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../../../../../src/EnsoShortcuts.sol";
import { IntentRouter_Unit_Concrete_Test } from "./IntentRouter.t.sol";

contract IntentRouter_Constructor_Unit_Concrete_Test is IntentRouter_Unit_Concrete_Test {
    function test_Constructor() external {
        // it should deploy shortcuts executed only by the router
        EnsoShortcuts shortcuts = EnsoShortcuts(payable(s_shortcuts));
        assertEq(shortcuts.executor(), address(s_router));
        vm.prank(s_keeper);
        vm.expectRevert(EnsoShortcuts.NotPermitted.selector);
        shortcuts.executeShortcut(bytes32(0), bytes32(0), new bytes32[](0), new bytes[](0));

        // it should expose the EIP-712 domain
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            s_router.eip712Domain();
        assertEq(name, "IntentRouter");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(s_router));
    }
}

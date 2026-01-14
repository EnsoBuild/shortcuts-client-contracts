// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";

contract EnsoCCIPReceiver_Constructor_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_WhenDeployed() external {
        // Act & Assert
        vm.prank(s_deployer);
        EnsoCCIPReceiver ensoCcipReceiver = new EnsoCCIPReceiver(s_owner, address(s_ccipRouter), address(s_ensoRouter));

        // it should set owner
        assertTrue(ensoCcipReceiver.owner() == s_owner);

        // it should set ccipRouter
        assertTrue(ensoCcipReceiver.getRouter() == address(s_ccipRouter));

        // it should set ensoRouter
        assertTrue(ensoCcipReceiver.getEnsoRouter() == address(s_ensoRouter));
    }
}

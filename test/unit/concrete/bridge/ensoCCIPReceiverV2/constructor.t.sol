// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiverV2 } from "../../../../../src/bridge/EnsoCCIPReceiverV2.sol";
import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";

contract EnsoCCIPReceiverV2_Constructor_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test {
    function test_WhenDeployed() external {
        // Act & Assert
        vm.prank(s_deployer);
        EnsoCCIPReceiverV2 ensoCcipReceiver =
            new EnsoCCIPReceiverV2(s_owner, address(s_ccipRouter), address(s_ensoRouter));

        // it should set owner
        assertTrue(ensoCcipReceiver.owner() == s_owner);

        // it should set ccipRouter
        assertTrue(ensoCcipReceiver.getRouter() == address(s_ccipRouter));

        // it should set ensoRouter
        assertTrue(ensoCcipReceiver.getEnsoRouter() == address(s_ensoRouter));
    }
}

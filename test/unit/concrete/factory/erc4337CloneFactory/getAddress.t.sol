pragma solidity ^0.8.28;

import { ERC4337CloneFactory_Unit_Concrete_Test } from "./ERC4337CloneFactory.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";

contract ERC4337CloneFactory_GetAddress_Unit_Concrete_Test is ERC4337CloneFactory_Unit_Concrete_Test {
    function test_ShouldReturnCounterfactualEnsoReceiverAddress() external view {
        // it should return counterfactual EnsoReceiver address
        assertEq(s_cloneFactory.getAddress(s_owner), 0x3B371323Fc00bD13aF19D7269Ea86fF7bE2C3304);
    }
}

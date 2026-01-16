pragma solidity ^0.8.28;

import { ERC4337CloneFactory_Unit_Concrete_Test } from "./ERC4337CloneFactory.t.sol";
import { console2 } from "forge-std/Test.sol";

contract ERC4337CloneFactory_GetDelegateAddress_Unit_Concrete_Test is ERC4337CloneFactory_Unit_Concrete_Test {
    function test_ShouldReturnCounterfactualEnsoReceiverAddress() external view {
        // it should return counterfactual EnsoReceiver address
        assertEq(s_cloneFactory.getDelegateAddress(s_owner, s_signer), 0x18019a4eB1b512eB9A7096DEeB6BF720439EdFf4);
    }
}

pragma solidity ^0.8.28;

import { ERC4337CloneFactory_Unit_Concrete_Test } from "./ERC4337CloneFactory.t.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract ERC4337CloneFactory_GetAddress_Unit_Concrete_Test is ERC4337CloneFactory_Unit_Concrete_Test {
    function test_ShouldReturnCounterfactualEnsoReceiverAddress() external view {
        bytes32 salt = keccak256(abi.encode(s_owner, s_owner));
        address expected = vm.computeCreate2Address(
            salt, LibClone.initCodeHash(address(s_ensoReceiverIpml)), address(s_cloneFactory)
        );
        assertEq(s_cloneFactory.getAddress(s_owner), expected);
    }
}

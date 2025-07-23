// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";

import { console2 } from "forge-std-1.9.7/Test.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

contract EnsoReceiver_Initialize_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test {
    function test_RevertWhen_AlreadyInitialized() external {
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        s_ensoReceiver.initialize(s_owner, s_signer, address(s_entryPoint));
    }

    function test_WhenNotInitialized() external {
        EnsoReceiver ensoReceiver = new EnsoReceiver();
        ensoReceiver.initialize(s_owner, s_signer, address(s_entryPoint));

        // it should set owner
        assertEq(ensoReceiver.owner(), s_owner);

        // it should set signer
        assertEq(ensoReceiver.signer(), s_signer);

        // it should set entryPoint
        assertEq(address(ensoReceiver.entryPoint()), address(s_entryPoint));
    }
}

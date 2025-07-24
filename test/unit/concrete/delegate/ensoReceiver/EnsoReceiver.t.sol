// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { EnsoShortcutsHelpers } from "../../../../../src/helpers/EnsoShortcutsHelpers.sol";
import { WETH9 } from "../../../../mocks/WETH9.sol";
import { EntryPoint } from "account-abstraction-v7/core/EntryPoint.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

abstract contract EnsoReceiver_Unit_Concrete_Test is Test {
    address payable internal constant EOA_1 = payable(0xE150e171dDf7ef6785e2c6fBBbE9eCd0f2f63682);
    bytes32 internal constant EOA_1_PK = 0x74dc97524c0473f102953ebfe8bbec30f0e9cd304703ed7275c708921deaab3b;

    address payable internal s_deployer;
    address payable internal s_owner;
    address payable internal s_account3;
    address payable internal s_account4;
    address payable internal s_signer;
    bytes32 internal s_signerPk;
    EntryPoint internal s_entryPoint;
    EnsoReceiver internal s_ensoReceiver;
    EnsoShortcutsHelpers internal s_ensoShortcutsHelpers;
    WETH9 internal s_weth;

    function setUp() public virtual {
        s_signer = EOA_1;
        vm.label(EOA_1, "EOA_1");
        s_signerPk = EOA_1_PK;

        s_deployer = payable(vm.addr(1));
        vm.deal(s_deployer, 1000 ether);
        vm.label(s_deployer, "Deployer");

        s_owner = payable(vm.addr(2));
        vm.deal(s_owner, 1000 ether);
        vm.label(s_owner, "Owner");

        s_account3 = payable(vm.addr(3));
        vm.deal(s_account3, 1000 ether);
        vm.label(s_account3, "Account_3");

        s_account4 = payable(vm.addr(4));
        vm.deal(s_account4, 1000 ether);
        vm.label(s_account4, "Account_4");

        vm.startPrank(s_deployer);
        s_entryPoint = new EntryPoint();
        vm.label(address(s_entryPoint), "EntryPoint_0_7");

        s_ensoReceiver = new EnsoReceiver();
        s_ensoReceiver.initialize(s_owner, s_signer, address(s_entryPoint));
        vm.label(address(s_ensoReceiver), "EnsoReceiver");

        s_weth = new WETH9();
        vm.label(address(s_weth), "WETH9");

        s_ensoShortcutsHelpers = new EnsoShortcutsHelpers();
        vm.label(address(s_ensoShortcutsHelpers), "EnsoShortcutsHelpers");
        vm.stopPrank();
    }
}

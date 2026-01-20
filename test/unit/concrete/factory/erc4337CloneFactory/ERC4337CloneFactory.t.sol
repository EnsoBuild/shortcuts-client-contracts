// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../../../../../src/factory/ERC4337CloneFactory.sol";
import { Test } from "forge-std/Test.sol";

abstract contract ERC4337CloneFactory_Unit_Concrete_Test is Test {
    address payable internal s_deployer;
    address payable internal s_owner;
    address payable internal s_account3;
    address payable internal s_account4;
    address payable internal s_signer;

    address internal s_entryPoint;
    EnsoReceiver internal s_ensoReceiverIpml;
    ERC4337CloneFactory internal s_cloneFactory;

    function setUp() public virtual {
        s_deployer = payable(vm.addr(1));
        vm.deal(s_deployer, 1000 ether);
        vm.label(s_deployer, "Deployer");

        s_owner = payable(vm.addr(3));
        vm.deal(s_owner, 1000 ether);
        vm.label(s_owner, "Owner");

        s_account3 = payable(vm.addr(3));
        vm.deal(s_account3, 1000 ether);
        vm.label(s_account3, "Account_3");

        s_account4 = payable(vm.addr(4));
        vm.deal(s_account4, 1000 ether);
        vm.label(s_account4, "Account_4");

        s_entryPoint = address(777);
        vm.label(address(s_entryPoint), "EntryPoint_0_7");

        vm.startPrank(s_deployer);
        s_ensoReceiverIpml = new EnsoReceiver();
        s_ensoReceiverIpml.initialize(address(0), address(0), address(0)); // Brick the implementation
        vm.label(address(s_ensoReceiverIpml), "EnsoReceiverImplementation");

        s_cloneFactory = new ERC4337CloneFactory(address(s_ensoReceiverIpml), s_entryPoint);
        vm.label(address(s_cloneFactory), "ERC4337CloneFactory");
        vm.stopPrank();
    }
}

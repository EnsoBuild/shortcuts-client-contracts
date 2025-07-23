// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { SignaturePaymaster } from "../../../../../src/paymaster/SignaturePaymaster.sol";
import { EntryPoint } from "account-abstraction-v7/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

abstract contract SignaturePaymaster_Unit_Concrete_Test is Test {
    address payable internal s_deployer;
    address payable internal s_owner;
    address payable internal s_account3;
    address payable internal s_account4;
    EntryPoint internal s_entryPoint;
    SignaturePaymaster internal s_signaturePaymaster;

    function setUp() public virtual {
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

        s_signaturePaymaster = new SignaturePaymaster(IEntryPoint(address(s_entryPoint)), s_owner);
        vm.label(address(s_signaturePaymaster), "SignaturePaymaster");
        vm.stopPrank();
    }
}

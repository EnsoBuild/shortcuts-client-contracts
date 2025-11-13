// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../../../../../src/EnsoShortcuts.sol";
import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { EnsoShortcutsHelpers } from "../../../../../src/helpers/EnsoShortcutsHelpers.sol";
import { EnsoRouter } from "../../../../../src/router/EnsoRouter.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { WETH9 } from "../../../../mocks/WETH9.sol";
import { MockCCIPRouter } from "chainlink-ccip/test/mocks/MockRouter.sol";
import { Test } from "forge-std-1.9.7/Test.sol";

abstract contract EnsoCCIPReceiver_Unit_Concrete_Test is Test {
    address payable internal s_deployer;
    address payable internal s_owner;
    address payable internal s_account1;
    address payable internal s_account2;
    EnsoRouter internal s_ensoRouter;
    EnsoShortcuts internal s_ensoShortcuts;
    EnsoShortcutsHelpers internal s_ensoShortcutsHelpers;
    MockCCIPRouter internal s_ccipRouter;
    EnsoCCIPReceiver internal s_ensoCcipReceiver;
    WETH9 internal s_weth;
    MockERC20 internal s_tokenA;
    MockERC20 internal s_tokenB;

    function setUp() public virtual {
        s_deployer = payable(vm.addr(1));
        vm.deal(s_deployer, 1000 ether);
        vm.label(s_deployer, "Deployer");

        s_owner = payable(vm.addr(2));
        vm.deal(s_owner, 1000 ether);
        vm.label(s_owner, "Owner");

        s_account1 = payable(vm.addr(3));
        vm.deal(s_account1, 1000 ether);
        vm.label(s_account1, "Account_1");

        s_account2 = payable(vm.addr(4));
        vm.deal(s_account2, 1000 ether);
        vm.label(s_account2, "Account_2");

        vm.startPrank(s_deployer);
        s_ensoRouter = new EnsoRouter();
        vm.label(address(s_ensoRouter), "EnsoRouter");

        s_ensoShortcuts = EnsoShortcuts(payable(s_ensoRouter.shortcuts()));
        vm.label(address(s_ensoShortcuts), "EnsoShortcuts");

        s_ensoShortcutsHelpers = new EnsoShortcutsHelpers();
        vm.label(address(s_ensoShortcutsHelpers), "EnsoShortcutsHelpers");

        s_ccipRouter = new MockCCIPRouter();
        vm.label(address(s_ccipRouter), "MockCCIPRouter");

        s_ensoCcipReceiver = new EnsoCCIPReceiver(s_owner, address(s_ccipRouter), address(s_ensoRouter));
        vm.label(address(s_ensoCcipReceiver), "EnsoCCIPReceiver");

        s_weth = new WETH9();
        vm.label(address(s_weth), "WETH9");

        s_tokenA = new MockERC20("Token A", "TKNA");
        vm.label(address(s_tokenA), "TKNA");
        s_tokenA.mint(s_deployer, 1000 ether);

        s_tokenB = new MockERC20("Token B", "TKNB");
        vm.label(address(s_tokenB), "TKNB");
        s_tokenB.mint(s_deployer, 1000 ether);

        vm.stopPrank();
    }
}

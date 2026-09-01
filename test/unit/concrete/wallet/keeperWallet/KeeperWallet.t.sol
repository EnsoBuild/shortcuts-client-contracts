// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { KeeperWallet } from "../../../../../src/wallet/KeeperWallet.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";

import { Test } from "forge-std/Test.sol";

contract Target {
    error Target_Revert();

    uint256 public counter;

    function func() external pure returns (uint256) {
        return 42;
    }

    function funcWithValue() external payable returns (uint256) {
        return msg.value;
    }

    function increment() external returns (uint256) {
        return ++counter;
    }

    function revertString() external pure {
        revert("Test revert");
    }

    function revertCustomError() external pure {
        revert Target_Revert();
    }

    function revertNoReason() external pure {
        revert();
    }
}

abstract contract KeeperWallet_Unit_Concrete_Test is Test {
    address payable internal s_owner;
    address payable internal s_executor;
    address payable internal s_user;

    KeeperWallet internal s_wallet;
    Target internal s_target;
    MockERC20 internal s_erc20;

    function setUp() public virtual {
        s_owner = payable(vm.addr(1));
        vm.deal(s_owner, 1000 ether);
        vm.label(s_owner, "Owner");

        s_executor = payable(vm.addr(2));
        vm.deal(s_executor, 1000 ether);
        vm.label(s_executor, "Executor");

        s_user = payable(vm.addr(3));
        vm.deal(s_user, 1000 ether);
        vm.label(s_user, "User");

        s_wallet = new KeeperWallet(s_owner);
        vm.label(address(s_wallet), "KeeperWallet");

        s_target = new Target();
        vm.label(address(s_target), "Target");

        s_erc20 = new MockERC20("Mock ERC20", "MERC20");
        vm.label(address(s_erc20), "MockERC20");

        vm.prank(s_owner);
        s_wallet.setExecutor(s_executor, true);
    }
}

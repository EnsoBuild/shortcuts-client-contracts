// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { IEnsoCCIPReceiver } from "../../../../../src/interfaces/IEnsoCCIPReceiver.sol";
import { Shortcut } from "../../../../shortcuts/ShortcutDataTypes.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoCCIP_ReceiverExecute_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    address private s_caller;

    function test_RevertWhen_CallerIsNotSelf() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEnsoCCIPReceiver.EnsoCCIPReceiver_OnlySelf.selector));
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(address(0), 0, "");
    }

    modifier whenCallerIsSelf() {
        s_caller = address(s_ensoCcipReceiver);
        _;
    }

    function test_RevertWhen_ShortcutExecutionFailed() external whenCallerIsSelf {
        // NOTE: force a shortcut failure by not providing allowance
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(0)));
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(address(0), 0, "0xdeadbeef");
    }

    function test_WhenShortcutExecutionSucceeded() external whenCallerIsSelf {
        // Arrange
        address token = address(s_tokenA);
        uint256 amount = 16 ether;

        uint256 ccipReceiverBalanceTokenABefore = balance(token, address(s_ensoCcipReceiver));
        uint256 ensoShortcutsBalanceTokenABefore = balance(token, address(s_ensoShortcuts));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act
        // NOTE: this shortcut just transfers the tokenIn to the EnsoShortcuts contract
        // it should apply shorcut state changes
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(address(s_tokenA), amount, "");

        // Assert
        uint256 ccipReceiverBalanceTokenAAfter = balance(token, address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore, ccipReceiverBalanceTokenAAfter, 0, "EnsoCCIPReceiver tokenIn (TKNA)"
        );
        uint256 ensoShortcutsBalanceTokenAAfter = balance(token, address(s_ensoShortcuts));
        assertBalanceDiff(
            ensoShortcutsBalanceTokenABefore,
            ensoShortcutsBalanceTokenAAfter,
            int256(amount),
            "EnsoShortcuts tokenIn (TKNA)"
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoCCIPReceiverV2 } from "../../../../../src/interfaces/IEnsoCCIPReceiverV2.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoCCIPReceiverV2_Unit_Concrete_Test } from "./EnsoCCIPReceiverV2.t.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoCCIPReceiverV2_Execute_Unit_Concrete_Test is EnsoCCIPReceiverV2_Unit_Concrete_Test, TokenBalanceHelper {
    address private s_caller;

    function test_RevertWhen_CallerIsNotSelf() external {
        // Arrange
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEnsoCCIPReceiverV2.EnsoCCIPReceiverV2_OnlySelf.selector));
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "");
    }

    modifier whenCallerIsSelf() {
        s_caller = address(s_ensoCcipReceiver);
        _;
    }

    function test_RevertWhen_ShortcutExecutionFailed() external whenCallerIsSelf {
        // Arrange
        // NOTE: force a failure by routing the zero address token (forceApprove reverts)
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(0)));
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "0xdeadbeef");
    }

    function test_RevertWhen_TokensLengthIsBelowMin() external whenCallerIsSelf {
        // Arrange: zero tokens
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        // Act & Assert
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IEnsoCCIPReceiverV2.EnsoCCIPReceiverV2_UnsupportedTokensLength.selector, 0)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "");
    }

    function test_RevertWhen_TokensLengthExceedsMax() external whenCallerIsSelf {
        // Arrange: 3 tokens > MAX_TOKENS (2)
        address[] memory tokens = new address[](3);
        tokens[0] = address(s_tokenA);
        tokens[1] = address(s_tokenB);
        tokens[2] = address(s_tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1 ether;

        // Act & Assert
        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IEnsoCCIPReceiverV2.EnsoCCIPReceiverV2_UnsupportedTokensLength.selector, 3)
        );
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "");
    }

    function test_WhenSingleToken() external whenCallerIsSelf {
        // Arrange
        address token = address(s_tokenA);
        uint256 amount = 16 ether;

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 ccipReceiverBalanceTokenABefore = balance(token, address(s_ensoCcipReceiver));
        uint256 ensoShortcutsBalanceTokenABefore = balance(token, address(s_ensoShortcuts));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);
        vm.stopPrank();

        // Act
        // NOTE: empty shortcut just transfers tokenIn to the EnsoShortcuts contract (routeSingle)
        // it should apply shortcut state changes
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "");

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

    function test_WhenTwoTokens() external whenCallerIsSelf {
        // Arrange
        uint256 amountA = 16 ether;
        uint256 amountB = 42 ether;

        address[] memory tokens = new address[](2);
        tokens[0] = address(s_tokenA);
        tokens[1] = address(s_tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountA;
        amounts[1] = amountB;

        uint256 ensoShortcutsBalanceTokenABefore = balance(address(s_tokenA), address(s_ensoShortcuts));
        uint256 ensoShortcutsBalanceTokenBBefore = balance(address(s_tokenB), address(s_ensoShortcuts));

        // NOTE: transfer tokens to EnsoCCIPReceiver contract to simulate CCIP Router behavior
        vm.startPrank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amountA);
        s_tokenB.transfer(address(s_ensoCcipReceiver), amountB);
        vm.stopPrank();

        // Act
        // NOTE: empty shortcut just transfers both tokensIn to the EnsoShortcuts contract (routeMulti)
        // it should apply shortcut state changes
        vm.prank(s_caller);
        s_ensoCcipReceiver.execute(tokens, amounts, "");

        // Assert
        uint256 ensoShortcutsBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoShortcuts));
        assertBalanceDiff(
            ensoShortcutsBalanceTokenABefore,
            ensoShortcutsBalanceTokenAAfter,
            int256(amountA),
            "EnsoShortcuts tokenIn (TKNA)"
        );
        uint256 ensoShortcutsBalanceTokenBAfter = balance(address(s_tokenB), address(s_ensoShortcuts));
        assertBalanceDiff(
            ensoShortcutsBalanceTokenBBefore,
            ensoShortcutsBalanceTokenBAfter,
            int256(amountB),
            "EnsoShortcuts tokenIn (TKNB)"
        );
        // it should consume both approvals from the EnsoCCIPReceiver
        uint256 ccipReceiverBalanceTokenAAfter = balance(address(s_tokenA), address(s_ensoCcipReceiver));
        assertEq(ccipReceiverBalanceTokenAAfter, 0, "EnsoCCIPReceiver tokenIn (TKNA)");
        uint256 ccipReceiverBalanceTokenBAfter = balance(address(s_tokenB), address(s_ensoCcipReceiver));
        assertEq(ccipReceiverBalanceTokenBAfter, 0, "EnsoCCIPReceiver tokenIn (TKNB)");
    }
}

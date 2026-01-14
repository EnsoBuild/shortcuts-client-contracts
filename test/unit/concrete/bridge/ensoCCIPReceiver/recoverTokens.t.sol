// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { IEnsoCCIPReceiver } from "../../../../../src/interfaces/IEnsoCCIPReceiver.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";

contract EnsoCCIPReceiver_RecoverTokens_Unit_Concrete_Test is EnsoCCIPReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    function test_RevertWhen_CallerIsNotOwner() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_account1));
        vm.prank(s_account1);
        s_ensoCcipReceiver.recoverTokens(address(0), address(0), 0);
    }

    function test_WhenCallerIsOwner() external {
        // Arrange
        address token = address(s_tokenA);
        address recipient = s_account2;
        uint256 amount = 42 ether;

        vm.prank(s_deployer);
        s_tokenA.transfer(address(s_ensoCcipReceiver), amount);

        uint256 ccipReceiverBalanceTokenABefore = balance(token, address(s_ensoCcipReceiver));
        uint256 recipientBalanceTokenABefore = balance(token, recipient);

        // Act & Assert
        // it should emit TokensRecovered
        vm.expectEmit(true, false, false, true);
        emit IEnsoCCIPReceiver.TokensRecovered(token, recipient, amount);
        vm.prank(s_owner);
        s_ensoCcipReceiver.recoverTokens(token, recipient, amount);

        // it should safe transfer amount to recipient
        uint256 ccipReceiverBalanceTokenAAfter = balance(token, address(s_ensoCcipReceiver));
        assertBalanceDiff(
            ccipReceiverBalanceTokenABefore,
            ccipReceiverBalanceTokenAAfter,
            -int256(amount),
            "EnsoCCIPReceiver token (TKNA)"
        );
        uint256 recipientBalanceTokenAAfter = balance(token, recipient);
        assertBalanceDiff(
            recipientBalanceTokenABefore, recipientBalanceTokenAAfter, int256(amount), "Recipient token (TKNA)"
        );
    }
}

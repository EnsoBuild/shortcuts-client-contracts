// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { EnsoCCIPReceiver } from "../../../../../src/bridge/EnsoCCIPReceiver.sol";
import { EnsoShortcutsHelpers } from "../../../../../src/helpers/EnsoShortcutsHelpers.sol";
import { IEnsoCCIPReceiver } from "../../../../../src/interfaces/IEnsoCCIPReceiver.sol";
import { EnsoRouter } from "../../../../../src/router/EnsoRouter.sol";
import { EnsoCCIPReceiver_Unit_Concrete_Test } from "./EnsoCCIPReceiver.t.sol";

contract EnsoCCIPReceiver_DecodeMessageData_Unit_Concrete is EnsoCCIPReceiver_Unit_Concrete_Test {
    function test_RevertWhen_MsgSenderIsNotSelf() external {
        // Act & Assert
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IEnsoCCIPReceiver.EnsoCCIPReceiver_OnlySelf.selector));
        vm.prank(s_account1);
        s_ensoCcipReceiver.decodeMessageData("");
    }

    modifier whenMsgSenderIsCcipSelf() {
        vm.startPrank(address(s_ensoCcipReceiver));
        _;
        vm.stopPrank();
    }

    function test_WhenDataIsMalformed() external whenMsgSenderIsCcipSelf {
        // Act & Assert
        // it should panic
        vm.expectRevert();
        s_ensoCcipReceiver.decodeMessageData("");
    }

    function test_WhenDataIsNotMalformed() external whenMsgSenderIsCcipSelf {
        // Arrange
        address receiver = address(777);
        uint256 estimatedGas = 1_000_000;
        bytes memory shortcutData = "";
        bytes memory data = abi.encode(receiver, estimatedGas, shortcutData);

        // Act
        (address decodedReceiver, uint256 decodedEstimatedGas, bytes memory decodedShortcutData) =
            s_ensoCcipReceiver.decodeMessageData(data);

        // Assert
        // it should return payload decoded
        assertEq(decodedReceiver, receiver);
        assertEq(decodedEstimatedGas, estimatedGas);
        assertEq(decodedShortcutData, shortcutData);
    }
}

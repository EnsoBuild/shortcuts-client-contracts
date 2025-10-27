// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "./EnsoWalletV2.t.sol";

contract EnsoWalletV2_Owner_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    function test_WhenWalletInitialized() external {
        // it should return correct owner
        s_wallet = _deployWallet(s_owner);
        assertEq(s_wallet.owner(), s_owner);
    }

    function test_WhenCalledByOwner() external {
        // it should allow owner-only functions
        s_wallet = _deployWallet(s_owner);

        vm.startPrank(s_owner);
        // This should not revert
        s_wallet.execute(s_user, 0, "");
    }

    function test_RevertWhen_NotOwner() external {
        // it should revert when not called by owner
        s_wallet = _deployWallet(s_owner);

        vm.startPrank(s_user);
        vm.expectRevert(abi.encodeWithSelector(EnsoWalletV2.InvalidSender.selector, s_user));
        s_wallet.execute(s_user, 0, "");
    }
}
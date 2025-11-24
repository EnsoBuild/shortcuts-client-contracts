// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "./EnsoWalletV2.t.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";

contract EnsoWalletV2_Initialize_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    function setUp() public override {
        super.setUp();

        s_wallet = _deployWallet(s_owner);
    }

    function test_RevertWhen_AlreadyInitialized() external {
        // it should revert when trying to initialize again
        vm.startPrank(address(s_walletFactory));
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        s_wallet.initialize(s_owner);
    }
}


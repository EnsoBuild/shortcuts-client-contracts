// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "./EnsoWalletV2.t.sol";

contract EnsoWalletV2_Version_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    function test_WhenCalled() external {
        s_wallet = _deployWallet(s_owner);
        assertEq(keccak256(bytes(s_wallet.VERSION())) == keccak256(bytes("1.0.0")), true);
    }
}

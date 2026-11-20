// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Constraints, Intent } from "../../../../../src/interfaces/IIntent.sol";
import {
    EphemeralIntentExecutor_Unit_Concrete_Test
} from "../../wallet/ephemeralIntentExecutor/EphemeralIntentExecutor.t.sol";

abstract contract EphemeralFactory_Unit_Concrete_Test is EphemeralIntentExecutor_Unit_Concrete_Test {
    uint256 internal constant DEPOSIT = 100 ether;

    function _swapIntent() internal view returns (Intent memory) {
        Constraints memory c =
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), DEPOSIT, 2e18, 0, 0, Codes.DRAIN);
        return _intent(c, s_user, s_keeper);
    }
}

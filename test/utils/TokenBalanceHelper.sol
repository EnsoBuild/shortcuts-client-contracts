// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std-1.9.7/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokenBalanceHelper is Test {
    address internal constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function assertBalanceDiff(
        uint256 balancePre,
        uint256 balancePost,
        int256 expectedDiff,
        string memory label
    )
        internal
        pure
    {
        int256 actualDiff = int256(balancePost) - int256(balancePre);
        assertEq(actualDiff, expectedDiff, string(abi.encodePacked("Balance diff mismatch: ", label)));
    }

    function balance(address token, address account) internal view returns (uint256 balance_) {
        balance_ = token == NATIVE_ASSET ? account.balance : IERC20(token).balanceOf(account);
    }
}

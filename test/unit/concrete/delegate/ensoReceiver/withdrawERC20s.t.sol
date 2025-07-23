// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { Withdrawable } from "../../../../../src/utils/Withdrawable.sol";

import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";
import { IERC20Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract EnsoReceiver_WithdrawERC20s_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    MockERC20 s_erc20A;
    MockERC20 s_erc20B;

    function setUp() public virtual override {
        super.setUp();

        s_erc20A = new MockERC20("Token A", "TKNA");
        s_erc20B = new MockERC20("Token B", "TKNB");
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        IERC20[] memory erc20s = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.withdrawERC20s(erc20s, amounts);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ArrayLengthsAreNotEqual() external whenCallerIsOwner {
        IERC20[] memory erc20s = new IERC20[](1);
        erc20s[0] = IERC20(address(0));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 777;
        amounts[1] = 42;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(Withdrawable.ArrayLengthMismatch.selector, erc20s.length, amounts.length)
        );
        s_ensoReceiver.withdrawERC20s(erc20s, amounts);
    }

    modifier whenArrayLengthsAreEqual() {
        _;
    }

    function test_RevertWhen_SafeTransferIsNotSuccessful() external whenCallerIsOwner whenArrayLengthsAreEqual {
        IERC20[] memory erc20s = new IERC20[](2);
        erc20s[0] = IERC20(address(s_erc20A));
        erc20s[1] = IERC20(address(s_erc20B));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.7 ether;
        amounts[1] = 0.3 ether;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(s_ensoReceiver),
                s_erc20A.balanceOf(address(s_ensoReceiver)),
                amounts[0]
            )
        );
        s_ensoReceiver.withdrawERC20s(erc20s, amounts);
    }

    function test_WhenSafeTransferIsSuccessful() external whenCallerIsOwner whenArrayLengthsAreEqual {
        IERC20[] memory erc20s = new IERC20[](2);
        erc20s[0] = IERC20(address(s_erc20A));
        erc20s[1] = IERC20(address(s_erc20B));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.7 ether;
        amounts[1] = 0.3 ether;

        s_erc20A.mint(address(s_ensoReceiver), amounts[0]);
        s_erc20B.mint(address(s_ensoReceiver), amounts[1]);

        // Get balances before withdrawal
        uint256 ensoReceiverBalanceTknAPre = balance(address(s_erc20A), address(s_ensoReceiver));
        uint256 ensoReceiverBalanceTknBPre = balance(address(s_erc20B), address(s_ensoReceiver));
        uint256 ownerBalanceTknAPre = balance(address(s_erc20A), address(s_owner));
        uint256 ownerBalanceTknBPre = balance(address(s_erc20B), address(s_owner));

        s_ensoReceiver.withdrawERC20s(erc20s, amounts);

        // Get balances after withdrawal
        uint256 ensoReceiverBalanceTknAPost = balance(address(s_erc20A), address(s_ensoReceiver));
        uint256 ensoReceiverBalanceTknBPost = balance(address(s_erc20B), address(s_ensoReceiver));
        uint256 ownerBalanceTknAPost = balance(address(s_erc20A), address(s_owner));
        uint256 ownerBalanceTknBPost = balance(address(s_erc20B), address(s_owner));

        // it should transfer amount to owner
        assertBalanceDiff(
            ensoReceiverBalanceTknAPre, ensoReceiverBalanceTknAPost, -int256(amounts[0]), "EnsoReceiver TKNA"
        );
        assertBalanceDiff(
            ensoReceiverBalanceTknBPre, ensoReceiverBalanceTknBPost, -int256(amounts[1]), "EnsoReceiver TKNB"
        );
        assertBalanceDiff(ownerBalanceTknAPre, ownerBalanceTknAPost, int256(amounts[0]), "Owner TKNA");
        assertBalanceDiff(ownerBalanceTknBPre, ownerBalanceTknBPost, int256(amounts[1]), "Owner TKNB");
    }
}

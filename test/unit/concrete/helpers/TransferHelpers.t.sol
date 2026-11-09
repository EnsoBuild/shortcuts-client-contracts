// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { TransferHelpers } from "../../../../src/helpers/TransferHelpers.sol";
import { MockERC20 } from "../../../mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// Rejects every incoming native transfer, including zero-value calls.
contract RejectingReceiver {
    receive() external payable {
        revert("REJECT");
    }
}

contract TransferHelpersTest is Test {
    TransferHelpers public helpers;
    MockERC20 public token;

    IERC20 internal constant ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 internal constant AMOUNT = 1 ether;
    uint256 internal constant MAX_AMOUNT = 0.75 ether;

    address internal receiver;
    address internal feeReceiver;

    function setUp() public {
        helpers = new TransferHelpers();
        token = new MockERC20("Mock", "MOCK");
        receiver = makeAddr("receiver");
        feeReceiver = makeAddr("feeReceiver");

        vm.deal(address(this), 10 ether);
        token.mint(address(this), 10 ether);
        token.approve(address(helpers), type(uint256).max);
    }

    // ---------------------------------------------------------------------
    // Native token
    // ---------------------------------------------------------------------

    function test_transferWithLimit_eth_underMax_sendsAllToReceiver() public {
        uint256 amount = MAX_AMOUNT - 1;

        uint256 returned = helpers.transferWithLimit{ value: amount }(ETH, amount, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, amount, "returned");
        assertEq(receiver.balance, amount, "receiver");
        assertEq(feeReceiver.balance, 0, "feeReceiver");
        assertEq(address(helpers).balance, 0, "no dust left in helper");
    }

    function test_transferWithLimit_eth_atMax_sendsAllToReceiver() public {
        uint256 returned =
            helpers.transferWithLimit{ value: MAX_AMOUNT }(ETH, MAX_AMOUNT, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, MAX_AMOUNT, "returned");
        assertEq(receiver.balance, MAX_AMOUNT, "receiver");
        assertEq(feeReceiver.balance, 0, "feeReceiver");
        assertEq(address(helpers).balance, 0, "no dust left in helper");
    }

    function test_transferWithLimit_eth_overMax_splitsSurplusToFeeReceiver() public {
        uint256 returned = helpers.transferWithLimit{ value: AMOUNT }(ETH, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, MAX_AMOUNT, "returned");
        assertEq(receiver.balance, MAX_AMOUNT, "receiver");
        assertEq(feeReceiver.balance, AMOUNT - MAX_AMOUNT, "feeReceiver");
        assertEq(address(helpers).balance, 0, "no dust left in helper");
    }

    function test_transferWithLimit_eth_zeroMax_disablesCap() public {
        uint256 returned = helpers.transferWithLimit{ value: AMOUNT }(ETH, AMOUNT, 0, receiver, feeReceiver);

        assertEq(returned, AMOUNT, "returned");
        assertEq(receiver.balance, AMOUNT, "receiver gets everything");
        assertEq(feeReceiver.balance, 0, "no fee taken");
        assertEq(address(helpers).balance, 0, "no dust left in helper");
    }

    function test_transferWithLimit_eth_zeroAmount_isNoop() public {
        // Both parties reject calls, so any zero-value call would revert.
        address rejecting = address(new RejectingReceiver());

        uint256 returned = helpers.transferWithLimit(ETH, 0, MAX_AMOUNT, rejecting, rejecting);

        assertEq(returned, 0, "returned");
        assertEq(rejecting.balance, 0, "nothing sent");
    }

    function test_transferWithLimit_eth_revertsWhenValueBelowAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.IncorrectValue.selector, AMOUNT, AMOUNT - 1));
        helpers.transferWithLimit{ value: AMOUNT - 1 }(ETH, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);
    }

    function test_transferWithLimit_eth_revertsWhenValueAboveAmount() public {
        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.IncorrectValue.selector, AMOUNT, AMOUNT + 1));
        helpers.transferWithLimit{ value: AMOUNT + 1 }(ETH, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);
    }

    function test_transferWithLimit_eth_revertsWhenValueSentWithZeroAmount() public {
        // Guards against native value getting stranded in the helper.
        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.IncorrectValue.selector, 0, AMOUNT));
        helpers.transferWithLimit{ value: AMOUNT }(ETH, 0, MAX_AMOUNT, receiver, feeReceiver);
    }

    function test_transferWithLimit_eth_revertsWhenReceiverRejects() public {
        address rejecting = address(new RejectingReceiver());

        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.TransferFailed.selector, rejecting));
        helpers.transferWithLimit{ value: AMOUNT }(ETH, AMOUNT, MAX_AMOUNT, rejecting, feeReceiver);
    }

    function test_transferWithLimit_eth_revertsWhenFeeReceiverRejects() public {
        address rejecting = address(new RejectingReceiver());

        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.TransferFailed.selector, rejecting));
        helpers.transferWithLimit{ value: AMOUNT }(ETH, AMOUNT, MAX_AMOUNT, receiver, rejecting);
    }

    // ---------------------------------------------------------------------
    // ERC20
    // ---------------------------------------------------------------------

    function test_transferWithLimit_erc20_underMax_sendsAllToReceiver() public {
        uint256 amount = MAX_AMOUNT - 1;
        uint256 callerBefore = token.balanceOf(address(this));

        uint256 returned = helpers.transferWithLimit(token, amount, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, amount, "returned");
        assertEq(token.balanceOf(receiver), amount, "receiver");
        assertEq(token.balanceOf(feeReceiver), 0, "feeReceiver");
        assertEq(token.balanceOf(address(this)), callerBefore - amount, "caller debited");
        assertEq(token.balanceOf(address(helpers)), 0, "helper holds nothing");
    }

    function test_transferWithLimit_erc20_atMax_sendsAllToReceiver() public {
        uint256 returned = helpers.transferWithLimit(token, MAX_AMOUNT, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, MAX_AMOUNT, "returned");
        assertEq(token.balanceOf(receiver), MAX_AMOUNT, "receiver");
        assertEq(token.balanceOf(feeReceiver), 0, "feeReceiver");
    }

    function test_transferWithLimit_erc20_overMax_splitsSurplusToFeeReceiver() public {
        uint256 callerBefore = token.balanceOf(address(this));

        uint256 returned = helpers.transferWithLimit(token, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, MAX_AMOUNT, "returned");
        assertEq(token.balanceOf(receiver), MAX_AMOUNT, "receiver");
        assertEq(token.balanceOf(feeReceiver), AMOUNT - MAX_AMOUNT, "feeReceiver");
        assertEq(token.balanceOf(address(this)), callerBefore - AMOUNT, "caller debited the full amount");
        assertEq(token.balanceOf(address(helpers)), 0, "helper holds nothing");
    }

    function test_transferWithLimit_erc20_zeroMax_disablesCap() public {
        uint256 returned = helpers.transferWithLimit(token, AMOUNT, 0, receiver, feeReceiver);

        assertEq(returned, AMOUNT, "returned");
        assertEq(token.balanceOf(receiver), AMOUNT, "receiver gets everything");
        assertEq(token.balanceOf(feeReceiver), 0, "no fee taken");
    }

    function test_transferWithLimit_erc20_zeroAmount_isNoop() public {
        // With no allowance, any transferFrom would revert.
        token.approve(address(helpers), 0);

        uint256 returned = helpers.transferWithLimit(token, 0, MAX_AMOUNT, receiver, feeReceiver);

        assertEq(returned, 0, "returned");
        assertEq(token.balanceOf(receiver), 0, "nothing sent");
    }

    function test_transferWithLimit_erc20_revertsWhenValueSent() public {
        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.IncorrectValue.selector, 0, 1));
        helpers.transferWithLimit{ value: 1 }(token, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);
    }

    function test_transferWithLimit_erc20_revertsWithoutAllowance() public {
        token.approve(address(helpers), 0);

        // The surplus leg is pulled first, so it is the amount the allowance check reports.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(helpers), 0, AMOUNT - MAX_AMOUNT
            )
        );
        helpers.transferWithLimit(token, AMOUNT, MAX_AMOUNT, receiver, feeReceiver);
    }
}

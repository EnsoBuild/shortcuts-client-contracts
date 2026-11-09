// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import { TransferHelpers } from "../../../../../src/helpers/TransferHelpers.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract TransferHelpers_TransferWithLimit_Unit_Fuzz_Test is Test {
    TransferHelpers internal helpers;
    MockERC20 internal token;

    IERC20 internal constant ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 internal constant SUPPLY = 1_000_000 ether;

    address internal receiver;
    address internal feeReceiver;

    function setUp() public {
        helpers = new TransferHelpers();
        token = new MockERC20("Mock", "MOCK");
        receiver = makeAddr("receiver");
        feeReceiver = makeAddr("feeReceiver");

        vm.deal(address(this), SUPPLY);
        token.mint(address(this), SUPPLY);
        token.approve(address(helpers), type(uint256).max);
    }

    function testFuzz_eth_splitConservesAmount(uint256 _amount, uint256 _maxAmount) external {
        // Arrange
        uint256 amount = bound(_amount, 0, SUPPLY);
        (uint256 expectedReceiver, uint256 expectedFee) = _expectedSplit(amount, _maxAmount);

        // Act
        uint256 returned = helpers.transferWithLimit{ value: amount }(ETH, amount, _maxAmount, receiver, feeReceiver);

        // Assert
        // it should return what the receiver got
        assertEq(returned, expectedReceiver, "returned");
        // it should cap the receiver at maxAmount unless maxAmount is zero
        assertEq(receiver.balance, expectedReceiver, "receiver");
        // it should send exactly the surplus to the fee receiver
        assertEq(feeReceiver.balance, expectedFee, "feeReceiver");
        // it should never take more than the amount from the caller
        assertEq(receiver.balance + feeReceiver.balance, amount, "conservation");
        // it should never retain value
        assertEq(address(helpers).balance, 0, "no dust");
    }

    function testFuzz_erc20_splitConservesAmount(uint256 _amount, uint256 _maxAmount) external {
        // Arrange
        uint256 amount = bound(_amount, 0, SUPPLY);
        (uint256 expectedReceiver, uint256 expectedFee) = _expectedSplit(amount, _maxAmount);

        // Act
        uint256 returned = helpers.transferWithLimit(token, amount, _maxAmount, receiver, feeReceiver);

        // Assert
        // it should return what the receiver got
        assertEq(returned, expectedReceiver, "returned");
        // it should cap the receiver at maxAmount unless maxAmount is zero
        assertEq(token.balanceOf(receiver), expectedReceiver, "receiver");
        // it should send exactly the surplus to the fee receiver
        assertEq(token.balanceOf(feeReceiver), expectedFee, "feeReceiver");
        // it should debit the caller by exactly the amount
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "caller debited");
        // it should never retain tokens
        assertEq(token.balanceOf(address(helpers)), 0, "no dust");
    }

    function testFuzz_eth_revertsOnValueMismatch(uint256 _amount, uint256 _value, uint256 _maxAmount) external {
        // Arrange
        uint256 amount = bound(_amount, 0, SUPPLY);
        uint256 value = bound(_value, 0, SUPPLY);
        vm.assume(amount != value);

        // Act / Assert
        // it should revert with IncorrectValue whenever msg.value differs from amount
        vm.expectRevert(abi.encodeWithSelector(TransferHelpers.IncorrectValue.selector, amount, value));
        helpers.transferWithLimit{ value: value }(ETH, amount, _maxAmount, receiver, feeReceiver);
    }

    /// Zero `maxAmount` disables the cap; otherwise the receiver gets at most `maxAmount`.
    function _expectedSplit(uint256 amount, uint256 maxAmount) internal pure returns (uint256, uint256) {
        uint256 toReceiver = (maxAmount == 0 || amount <= maxAmount) ? amount : maxAmount;
        return (toReceiver, amount - toReceiver);
    }
}

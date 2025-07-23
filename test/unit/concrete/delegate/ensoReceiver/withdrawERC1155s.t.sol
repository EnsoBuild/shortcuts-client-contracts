// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";

import { MockERC1155 } from "../../../../mocks/MockERC1155.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";
import { IERC1155Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

contract EnsoReceiver_WithdrawERC1155s_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    MockERC1155 s_erc1155;

    function setUp() public virtual override {
        super.setUp();

        s_erc1155 = new MockERC1155("https://example.com/api/item/{id}.json");
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 777;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.withdrawERC1155s(s_erc1155, ids, amounts);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    // NOTE: this check is done by OpenZeppelin `ERC1155.safeBatchTransferFrom()`
    function test_RevertWhen_ArrayLengthsAreNotEqual() external whenCallerIsOwner {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 42;
        amounts[1] = 777;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidArrayLength.selector, ids.length, amounts.length)
        );
        s_ensoReceiver.withdrawERC1155s(s_erc1155, ids, amounts);
    }

    modifier whenArrayLengthsAreEqual() {
        _;
    }

    function test_RevertWhen_SafeBatchTransferIsNotSuccessful() external whenCallerIsOwner whenArrayLengthsAreEqual {
        s_erc1155.mint(address(s_ensoReceiver), 0, 42);
        s_erc1155.mint(address(s_ensoReceiver), 1, 777);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 42;
        amounts[1] = 777 + 1;

        // it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector,
                address(s_ensoReceiver),
                amounts[1] - 1,
                amounts[1],
                1
            )
        );
        s_ensoReceiver.withdrawERC1155s(s_erc1155, ids, amounts);
    }

    function test_WhenSafeBatchTransferIsSuccessful() external whenCallerIsOwner whenArrayLengthsAreEqual {
        s_erc1155.mint(address(s_ensoReceiver), 0, 42);
        s_erc1155.mint(address(s_ensoReceiver), 1, 777);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 42;
        amounts[1] = 777;

        // Get balances before withdrawal
        uint256 ensoReceiverBalanceErc1155_0_Pre = balance(address(s_erc1155), 0, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceErc1155_1_Pre = balance(address(s_erc1155), 1, address(s_ensoReceiver));
        uint256 ownerBalanceERC1155_0_Pre = balance(address(s_erc1155), 0, address(s_owner));
        uint256 ownerBalanceERC1155_1_Pre = balance(address(s_erc1155), 1, address(s_owner));

        s_ensoReceiver.withdrawERC1155s(s_erc1155, ids, amounts);

        // Get balances after withdrawal
        uint256 ensoReceiverBalanceErc1155_0_Post = balance(address(s_erc1155), 0, address(s_ensoReceiver));
        uint256 ensoReceiverBalanceErc1155_1_Post = balance(address(s_erc1155), 1, address(s_ensoReceiver));
        uint256 ownerBalanceERC1155_0_Post = balance(address(s_erc1155), 0, address(s_owner));
        uint256 ownerBalanceERC1155_1_Post = balance(address(s_erc1155), 1, address(s_owner));

        // it should transfer amount to owner
        assertBalanceDiff(
            ensoReceiverBalanceErc1155_0_Pre,
            ensoReceiverBalanceErc1155_0_Post,
            -int256(amounts[0]),
            "EnsoReceiver ERC1155_0"
        );
        assertBalanceDiff(
            ensoReceiverBalanceErc1155_1_Pre,
            ensoReceiverBalanceErc1155_1_Post,
            -int256(amounts[1]),
            "EnsoReceiver ERC1155_1"
        );
        assertBalanceDiff(ownerBalanceERC1155_0_Pre, ownerBalanceERC1155_0_Post, int256(amounts[0]), "Owner ERC1155_0");
        assertBalanceDiff(ownerBalanceERC1155_1_Pre, ownerBalanceERC1155_1_Post, int256(amounts[1]), "Owner ERC1155_1");
    }
}

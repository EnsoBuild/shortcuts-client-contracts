// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../../../src/delegate/EnsoReceiver.sol";
import { MockERC721 } from "../../../../mocks/MockERC721.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { TokenBalanceHelper } from "../../../../utils/TokenBalanceHelper.sol";
import { EnsoReceiver_Unit_Concrete_Test } from "./EnsoReceiver.t.sol";
import { console2 } from "forge-std-1.9.7/Test.sol";
import { IERC721Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

contract EnsoReceiver_WithdrawERC721s_Unit_Concrete_Test is EnsoReceiver_Unit_Concrete_Test, TokenBalanceHelper {
    MockERC721 s_erc721;

    function setUp() public virtual override {
        super.setUp();

        s_erc721 = new MockERC721("NFT A", "NFTA");
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 777;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(EnsoReceiver.InvalidSender.selector, s_account3));
        vm.prank(s_account3);
        s_ensoReceiver.withdrawERC721s(s_erc721, ids);
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(s_owner);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_SafeTransferIsNotSuccessful() external whenCallerIsOwner {
        s_erc721.mint(address(s_ensoReceiver), 0);
        s_erc721.mint(address(s_ensoReceiver), 1);
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 2));
        s_ensoReceiver.withdrawERC721s(s_erc721, ids);
    }

    function test_WhenSafeTransferIsSuccessful() external whenCallerIsOwner {
        s_erc721.mint(address(s_ensoReceiver), 0);
        s_erc721.mint(address(s_ensoReceiver), 1);
        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        // Get balances before withdrawal
        uint256 ensoReceiverBalanceNftPre = balance(address(s_erc721), address(s_ensoReceiver));
        uint256 ownerBalanceNftPre = balance(address(s_erc721), address(s_owner));

        s_ensoReceiver.withdrawERC721s(s_erc721, ids);

        // Get balances after withdrawal
        uint256 ensoReceiverBalanceNftPost = balance(address(s_erc721), address(s_ensoReceiver));
        uint256 ownerBalanceNftPost = balance(address(s_erc721), address(s_owner));

        // it should transfer token to owner
        assertBalanceDiff(
            ensoReceiverBalanceNftPre, ensoReceiverBalanceNftPost, -int256(ids.length), "EnsoReceiver NFTA"
        );
        assertBalanceDiff(ownerBalanceNftPre, ownerBalanceNftPost, int256(ids.length), "EnsoReceiver NFTA");
    }
}

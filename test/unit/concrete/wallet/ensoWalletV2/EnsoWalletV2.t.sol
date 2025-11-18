// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { EnsoWalletV2Factory } from "../../../../../src/wallet/EnsoWalletV2Factory.sol";

import { MockERC1155 } from "../../../../mocks/MockERC1155.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockERC721 } from "../../../../mocks/MockERC721.sol";

import { Test } from "forge-std-1.9.7/Test.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";

abstract contract EnsoWalletV2_Unit_Concrete_Test is Test {
    address payable internal constant EOA_1 = payable(0xE150e171dDf7ef6785e2c6fBBbE9eCd0f2f63682);
    bytes32 internal constant EOA_1_PK = 0x74dc97524c0473f102953ebfe8bbec30f0e9cd304703ed7275c708921deaab3b;

    address payable internal s_deployer;
    address payable internal s_owner;
    address payable internal s_user;
    address payable internal s_account1;
    address payable internal s_account2;

    EnsoWalletV2 internal s_walletImplementation;
    EnsoWalletV2Factory internal s_walletFactory;
    EnsoWalletV2 internal s_wallet;

    MockERC20 internal s_erc20;
    MockERC721 internal s_erc721;
    MockERC1155 internal s_erc1155;

    function setUp() public virtual {
        s_deployer = payable(vm.addr(1));
        vm.deal(s_deployer, 1000 ether);
        vm.label(s_deployer, "Deployer");

        s_owner = payable(vm.addr(2));
        vm.deal(s_owner, 1000 ether);
        vm.label(s_owner, "Owner");

        s_user = payable(vm.addr(3));
        vm.deal(s_user, 1000 ether);
        vm.label(s_user, "User");

        s_account1 = payable(vm.addr(5));
        vm.deal(s_account1, 1000 ether);
        vm.label(s_account1, "Account 1");

        s_account2 = payable(vm.addr(6));
        vm.deal(s_account2, 1000 ether);
        vm.label(s_account2, "Account 2");

        vm.startPrank(s_deployer);

        // Deploy implementation
        s_walletImplementation = new EnsoWalletV2();
        vm.label(address(s_walletImplementation), "EnsoWalletV2Implementation");

        // Deploy factory
        s_walletFactory = new EnsoWalletV2Factory(address(s_walletImplementation));
        vm.label(address(s_walletFactory), "EnsoWalletV2Factory");

        // Deploy mock tokens
        s_erc20 = new MockERC20("Mock ERC20", "MERC20");
        vm.label(address(s_erc20), "MockERC20");

        s_erc721 = new MockERC721("Mock ERC721", "MERC721");
        vm.label(address(s_erc721), "MockERC721");

        s_erc1155 = new MockERC1155("Mock ERC1155");
        vm.label(address(s_erc1155), "MockERC1155");

        vm.stopPrank();
    }

    function _deployWallet(address owner) internal returns (EnsoWalletV2 wallet) {
        // vm.startPrank(s_factory);
        wallet = EnsoWalletV2(payable(s_walletFactory.deploy(owner)));
        // vm.stopPrank();
    }
}

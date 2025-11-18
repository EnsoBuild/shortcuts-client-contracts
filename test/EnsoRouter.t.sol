// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import "../src/EnsoShortcuts.sol";
import "../src/router/EnsoRouter.sol";

import "./mocks/MockERC1155.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";

import "./mocks/MockMultiVault.sol";
import "./mocks/MockNFTVault.sol";
import "./mocks/MockVault.sol";

import "./utils/WeirollPlanner.sol";

import { ERC1155Holder } from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC721Holder } from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";

contract EnsoRouterTest is Test, ERC721Holder, ERC1155Holder {
    EnsoRouter public router;
    EnsoShortcuts public shortcuts;
    MockERC20 public token;
    MockERC721 public nft;
    MockERC1155 public multiToken;
    MockVault public vault;
    MockNFTVault public nftVault;
    MockMultiVault public multiVault;

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    uint256 public constant AMOUNT = 10 ** 18;
    uint256 public constant TOKENID = 1;

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);
        router = new EnsoRouter();
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
        token = new MockERC20("Test", "TST");
        nft = new MockERC721("NFT", "NFT");
        multiToken = new MockERC1155("Multi");
        vault = new MockVault("Vault", "VLT", address(token));
        nftVault = new MockNFTVault("NFTVault", "VNFT", address(nft));
        multiVault = new MockMultiVault("MultiVault", address(multiToken));
        token.mint(address(this), AMOUNT * 10);
        nft.mint(address(this), TOKENID);
        multiToken.mint(address(this), TOKENID, AMOUNT * 10);
    }

    function testVaultDeposit() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(router), AMOUNT);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(this));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC20, abi.encode(address(vault), AMOUNT));

        router.safeRouteSingle(tokenIn, tokenOut, address(this), data);
        assertEq(AMOUNT, vault.balanceOf(address(this)));
    }

    function test_RevertWhen_VaultDepositNoApproval() public {
        vm.selectFork(_ethereumFork);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(this));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC20, abi.encode(address(vault), AMOUNT));

        vm.expectRevert();
        router.safeRouteSingle(tokenIn, tokenOut, address(this), data);
    }

    function test_RevertWhen_VaultDepositNoTransfer() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(router), AMOUNT);

        // Shortcut does not transfer funds after deposit
        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC20, abi.encode(address(vault), AMOUNT));

        vm.expectRevert();
        router.safeRouteSingle(tokenIn, tokenOut, address(this), data);
    }

    function testUnsafeVaultDepositNoTransfer() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(router), AMOUNT);

        // Shortcut does not transfer funds after deposit
        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));

        router.routeSingle(tokenIn, data);
        // Funds left in router's wallet!
        assertEq(AMOUNT, vault.balanceOf(address(shortcuts)));
    }

    function testRouteMulti() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(router), AMOUNT);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(this));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        tokensIn[1] = Token(TokenType.Native, abi.encode(uint256(1)));

        router.routeMulti{ value: 1 }(tokensIn, data);
        assertEq(AMOUNT, vault.balanceOf(address(this)));
    }

    function testSafeRouteMulti() public {
        vm.selectFork(_ethereumFork);

        token.approve(address(router), AMOUNT);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        commands[0] = WeirollPlanner.buildCommand(
            token.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(token)
        );

        commands[1] = WeirollPlanner.buildCommand(
            vault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(vault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            vault.transfer.selector,
            0x01, // call
            0x0201ffffffff, // 2 inputs
            0xff, // no output
            address(vault)
        );

        state[0] = abi.encode(address(vault));
        state[1] = abi.encode(AMOUNT);
        state[2] = abi.encode(address(this));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token(TokenType.ERC20, abi.encode(address(token), AMOUNT));
        tokensIn[1] = Token(TokenType.Native, abi.encode(uint256(1)));

        Token[] memory tokensOut = new Token[](1);
        tokensOut[0] = Token(TokenType.ERC20, abi.encode(address(vault), AMOUNT));

        router.safeRouteMulti{ value: 1 }(tokensIn, tokensOut, address(this), data);
        assertEq(AMOUNT, vault.balanceOf(address(this)));
    }

    function testNFTVaultDeposit() public {
        vm.selectFork(_ethereumFork);

        nft.approve(address(router), TOKENID);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](4);

        commands[0] = WeirollPlanner.buildCommand(
            nft.approve.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(nft)
        );

        commands[1] = WeirollPlanner.buildCommand(
            nftVault.deposit.selector,
            0x01, // call
            0x01ffffffffff, // 1 input
            0xff, // no output
            address(nftVault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            bytes4(keccak256("safeTransferFrom(address,address,uint256)")),
            0x01, // call
            0x030201ffffff, // 3 inputs
            0xff, // no output
            address(nftVault)
        );

        state[0] = abi.encode(address(nftVault));
        state[1] = abi.encode(TOKENID);
        state[2] = abi.encode(address(this));
        state[3] = abi.encode(address(shortcuts));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC721, abi.encode(address(nft), TOKENID));
        Token memory tokenOut = Token(TokenType.ERC721, abi.encode(address(nftVault), 1)); // token out is checking for
        // balance, which
        // should increase by 1

        router.safeRouteSingle(tokenIn, tokenOut, address(this), data);
        assertEq(1, nftVault.balanceOf(address(this)));
    }

    function testMultiVaultDeposit() public {
        vm.selectFork(_ethereumFork);

        multiToken.setApprovalForAll(address(router), true);

        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](7);

        commands[0] = WeirollPlanner.buildCommand(
            multiToken.setApprovalForAll.selector,
            0x01, // call
            0x0001ffffffff, // 2 inputs
            0xff, // no output
            address(multiToken)
        );

        commands[1] = WeirollPlanner.buildCommand(
            multiVault.deposit.selector,
            0x01, // call
            0x0203ffffffff, // 2 input
            0xff, // no output
            address(multiVault)
        );

        commands[2] = WeirollPlanner.buildCommand(
            multiVault.safeTransferFrom.selector,
            0x01, // call
            0x0504020386ff, // 5 inputs
            0xff, // no output
            address(multiVault)
        );

        state[0] = abi.encode(address(multiVault));
        state[1] = abi.encode(true);
        state[2] = abi.encode(TOKENID);
        state[3] = abi.encode(AMOUNT);
        state[4] = abi.encode(address(this));
        state[5] = abi.encode(address(shortcuts));
        state[6] = abi.encode(bytes("0x"));

        bytes memory data =
            abi.encodeWithSelector(shortcuts.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);

        Token memory tokenIn = Token(TokenType.ERC1155, abi.encode(address(multiToken), TOKENID, AMOUNT));
        Token memory tokenOut = Token(TokenType.ERC1155, abi.encode(address(multiVault), TOKENID, AMOUNT));

        router.safeRouteSingle(tokenIn, tokenOut, address(this), data);
        assertEq(AMOUNT, multiVault.balanceOf(address(this), TOKENID));
    }
}

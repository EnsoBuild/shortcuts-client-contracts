// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { EnsoWalletV2Factory } from "../../../../../src/factory/EnsoWalletV2Factory.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { IEnsoWalletV2Factory } from "../../../../../src/interfaces/IEnsoWalletV2Factory.sol";
import { EnsoWalletV2 } from "../../../../../src/wallet/EnsoWalletV2.sol";
import { WeirollPlanner } from "../../../../utils/WeirollPlanner.sol";
import { EnsoWalletV2_Unit_Concrete_Test } from "../ensoWalletV2/EnsoWalletV2.t.sol";
import { WETH } from "solady/tokens/WETH.sol";

contract Target {
    function func() external payable returns (uint256) {
        return 42;
    }

    function revertFunc() external pure {
        revert("Test revert");
    }
}

contract EnsoWalletV2Factory_DeployAndExecute_Unit_Concrete_Test is EnsoWalletV2_Unit_Concrete_Test {
    WETH weth;

    function setUp() public override {
        super.setUp();

        weth = new WETH();
    }

    function test_executeShortcutWithNative() external {
        // action:
        // wrap 1 ETH to WETH
        // transfer 1 WETH to s_account1

        // it should deploy wallet and execute with native token
        Token memory tokenIn = Token({ tokenType: TokenType.Native, data: "" });
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = tokenIn;

        uint256 value = 1 ether;

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        commands[1] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0100ffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(1 ether);
        state[1] = abi.encode(s_account1);

        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory executors = new address[](0);

        vm.startPrank(s_user);
        (address walletAddress,) =
            s_walletFactory.deployAndExecute{ value: value }(tokensIn, executeData, executors, false);

        // it should deploy wallet
        assertTrue(walletAddress.code.length > 0);

        // it should initialize wallet correctly
        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        assertEq(wallet.owner(), s_user);
        assertEq(wallet.factory(), address(s_walletFactory));

        // it should transfer value to wallet
        assertEq(weth.balanceOf(s_account1), value);
    }

    function test_executeShortcutWithERC20() external {
        // action:
        // transfer 1 WETH to s_account1

        uint256 value = 1 ether;
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(weth, value) });
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = tokenIn;

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](2);

        commands[0] = WeirollPlanner.buildCommand(
            weth.transfer.selector,
            0x01, // call
            0x0100ffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        state[0] = abi.encode(1 ether);
        state[1] = abi.encode(s_account1);

        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        vm.startPrank(s_user);

        // make sure user has enough WETH
        weth.deposit{ value: value }();
        weth.approve(address(s_walletFactory), value);

        address[] memory executors = new address[](0);

        vm.startPrank(s_user);
        (address walletAddress,) = s_walletFactory.deployAndExecute(tokensIn, executeData, executors, false);

        // it should deploy wallet
        assertTrue(walletAddress.code.length > 0);

        // it should initialize wallet correctly
        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        assertEq(wallet.owner(), s_user);
        assertEq(wallet.factory(), address(s_walletFactory));

        // it should transfer value to wallet
        assertEq(weth.balanceOf(s_account1), value);
    }

    function test_executeShortcutWithTwoERC721Ids() external {
        uint256 largeId = (uint256(1) << 128) + 7;
        s_erc721.mint(s_user, 0);
        s_erc721.mint(s_user, largeId);
        address expectedWallet = s_walletFactory.getAddress(s_user);
        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(s_erc721), uint256(0)) });
        tokensIn[1] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(s_erc721), largeId) });
        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](4);
        state[0] = abi.encode(expectedWallet);
        state[1] = abi.encode(s_account1);
        state[2] = abi.encode(uint256(0));
        state[3] = abi.encode(largeId);
        commands[0] =
            WeirollPlanner.buildCommand(s_erc721.transferFrom.selector, 0x01, 0x000102ffffff, 0xff, address(s_erc721));
        commands[1] =
            WeirollPlanner.buildCommand(s_erc721.transferFrom.selector, 0x01, 0x000103ffffff, 0xff, address(s_erc721));
        vm.startPrank(s_user);
        s_erc721.approve(address(s_walletFactory), 0);
        s_erc721.approve(address(s_walletFactory), largeId);
        (address wallet,) = s_walletFactory.deployAndExecute(
            tokensIn, _buildExecuteShortcutsCalldata(commands, state), new address[](0), false
        );
        vm.stopPrank();
        assertEq(wallet, expectedWallet);
        assertEq(s_erc721.ownerOf(0), s_account1);
        assertEq(s_erc721.ownerOf(largeId), s_account1);
        assertEq(s_erc721.balanceOf(wallet), 0);
    }

    function test_revert_secondERC721FundingRollsBackFirst() external {
        s_erc721.mint(s_user, 7);
        s_erc721.mint(s_user, 8);
        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(s_erc721), uint256(7)) });
        tokensIn[1] = Token({ tokenType: TokenType.ERC721, data: abi.encode(address(s_erc721), uint256(8)) });
        address wallet = s_walletFactory.getAddress(s_user);
        bytes memory executeData = _buildExecuteShortcutsCalldata(new bytes32[](0), new bytes[](0));
        vm.startPrank(s_user);
        s_erc721.approve(address(s_walletFactory), 7);
        vm.expectRevert();
        s_walletFactory.deployAndExecute(tokensIn, executeData, new address[](0), false);
        vm.stopPrank();
        assertEq(s_erc721.ownerOf(7), s_user);
        assertEq(s_erc721.ownerOf(8), s_user);
        assertEq(wallet.code.length, 0);
    }

    function test_executeShortcutWithExecutors() external {
        Token[] memory tokensIn = new Token[](0);

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);
        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory executors = new address[](1);
        executors[0] = s_account1;

        vm.startPrank(s_user);
        (address walletAddress,) = s_walletFactory.deployAndExecute(tokensIn, executeData, executors, false);

        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        assertTrue(wallet.executors(s_account1));
    }

    function test_executeShortcutWithExecutors_existingWallet() external {
        Token[] memory tokensIn = new Token[](0);

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);
        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory emptyExecutors = new address[](0);

        vm.startPrank(s_user);
        (address walletAddress,) = s_walletFactory.deployAndExecute(tokensIn, executeData, emptyExecutors, false);

        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        assertFalse(wallet.executors(s_account2));

        address[] memory executors = new address[](1);
        executors[0] = s_account2;

        (address walletAddress2,) = s_walletFactory.deployAndExecute(tokensIn, executeData, executors, false);
        assertEq(walletAddress2, walletAddress);
        assertTrue(wallet.executors(s_account2));
    }

    function test_executeShortcutWithExecutors_resetExecutors() external {
        Token[] memory tokensIn = new Token[](0);

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);
        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory executors = new address[](1);
        executors[0] = s_account1;

        vm.startPrank(s_user);
        (address walletAddress,) = s_walletFactory.deployAndExecute(tokensIn, executeData, executors, true);

        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        // executor should be revoked after execution
        assertFalse(wallet.executors(s_account1));
    }

    function test_executeShortcutWithExecutors_resetMultipleExecutors() external {
        Token[] memory tokensIn = new Token[](0);

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);
        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory executors = new address[](2);
        executors[0] = s_account1;
        executors[1] = s_account2;

        vm.startPrank(s_user);
        (address walletAddress,) = s_walletFactory.deployAndExecute(tokensIn, executeData, executors, true);

        EnsoWalletV2 wallet = EnsoWalletV2(payable(walletAddress));
        // all executors should be revoked after execution
        assertFalse(wallet.executors(s_account1));
        assertFalse(wallet.executors(s_account2));
    }

    function test_revert_ERC20WithNativeValue() external {
        uint256 value = 1 ether;
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(weth, value) });
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = tokenIn;

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        vm.startPrank(s_user);
        weth.deposit{ value: value }();
        weth.approve(address(s_walletFactory), value);

        address[] memory executors = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(IEnsoWalletV2Factory.EnsoWalletV2Factory_WrongMsgValue.selector, value, 0)
        );
        s_walletFactory.deployAndExecute{ value: value }(tokensIn, executeData, executors, false);
    }

    function test_revert_executeShortcut() external {
        Token memory tokenIn = Token({ tokenType: TokenType.Native, data: "" });
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = tokenIn;

        uint256 value = 1 ether;

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](1);

        commands[0] = WeirollPlanner.buildCommand(
            weth.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // 1 input
            0xff, // no output
            address(weth)
        );

        // should revert because not enough ETH
        state[0] = abi.encode(1 ether + 1);

        bytes memory executeData = _buildExecuteShortcutsCalldata(commands, state);

        address[] memory executors = new address[](0);

        vm.startPrank(s_user);
        vm.expectRevert();
        s_walletFactory.deployAndExecute{ value: value }(tokensIn, executeData, executors, false);
    }

    function _buildExecuteShortcutsCalldata(
        bytes32[] memory commands,
        bytes[] memory state
    )
        private
        view
        returns (bytes memory)
    {
        return abi.encodeWithSelector(s_wallet.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);
    }

    // function test_WhenCalledWithERC20() external {
    // // it should deploy wallet and execute with ERC20 token
    // uint256 tokenAmount = 100 * 1e18;
    // s_erc20.mint(s_user, tokenAmount);
    //
    // Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(s_erc20, tokenAmount) });
    //
    // bytes memory executeData = abi.encodeWithSelector(Target.func.selector);
    //
    // vm.startPrank(s_user);
    // s_erc20.approve(address(s_walletFactory), tokenAmount);
    // (address walletAddress, bool success) = s_walletFactory.deployAndExecute(tokenIn, executeData);
    //
    // // it should return success
    // assertTrue(success);
    //
    // // it should transfer tokens to wallet
    // assertEq(s_erc20.balanceOf(walletAddress), tokenAmount);
    // assertEq(s_erc20.balanceOf(s_user), 0);
    //}
    //
    // function test_WhenCalledWithERC721() external {
    // // it should deploy wallet and execute with ERC721 token
    // uint256 tokenId = 123;
    // s_erc721.mint(s_user, tokenId);
    //
    // Token memory tokenIn = Token({ tokenType: TokenType.ERC721, data: abi.encode(s_erc721, tokenId) });
    //
    // bytes memory executeData = abi.encodeWithSelector(Target.func.selector);
    //
    // vm.startPrank(s_user);
    // s_erc721.approve(address(s_walletFactory), tokenId);
    // (address walletAddress, bool success) = s_walletFactory.deployAndExecute(tokenIn, executeData);
    //
    // // it should return success
    // assertTrue(success);
    //
    // // it should transfer NFT to wallet
    // assertEq(s_erc721.ownerOf(tokenId), walletAddress);
    //}
    //
    // function test_WhenCalledWithERC1155() external {
    // // it should deploy wallet and execute with ERC1155 token
    // uint256 tokenId = 456;
    // uint256 tokenAmount = 50;
    // s_erc1155.mint(s_user, tokenId, tokenAmount);
    //
    // Token memory tokenIn =
    // Token({ tokenType: TokenType.ERC1155, data: abi.encode(s_erc1155, tokenId, tokenAmount) });
    //
    // bytes memory executeData = abi.encodeWithSelector(Target.func.selector);
    //
    // vm.startPrank(s_user);
    // s_erc1155.setApprovalForAll(address(s_walletFactory), true);
    // (address walletAddress, bool success) = s_walletFactory.deployAndExecute(tokenIn, executeData);
    //
    // // it should return success
    // assertTrue(success);
    //
    // // it should transfer tokens to wallet
    // assertEq(s_erc1155.balanceOf(walletAddress, tokenId), tokenAmount);
    // assertEq(s_erc1155.balanceOf(s_user, tokenId), 0);
    //}
    //
    // function test_ExecuteReverts() external {
    // // it should revert when execute data reverts
    // Token memory tokenIn = Token({ tokenType: TokenType.Native, data: "" });
    //
    // bytes memory executeData = abi.encodeWithSelector(Target.revert.selector);
    //
    // vm.startPrank(s_user);
    // (, bool success) = s_walletFactory.deployAndExecute(tokenIn, executeData);
    // assertFalse(success);
    //}
    //
    // function test_RevertWhen_WrongMsgValue() external {
    // // it should revert when msg.value is provided for non-native tokens
    // uint256 tokenAmount = 100 * 1e18;
    // s_erc20.mint(s_user, tokenAmount);
    //
    // Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(s_erc20, tokenAmount) });
    //
    // bytes memory executeData = abi.encodeWithSelector(Target.func.selector);
    // uint256 wrongValue = 0.1 ether;
    //
    // vm.startPrank(s_user);
    // s_erc20.approve(address(s_walletFactory), tokenAmount);
    // vm.expectRevert(abi.encodeWithSelector(EnsoWalletV2Factory.WrongMsgValue.selector, wrongValue, 0));
    // s_walletFactory.deployAndExecute{ value: wrongValue }(tokenIn, executeData);
    //}
}

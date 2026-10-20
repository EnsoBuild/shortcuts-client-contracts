// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IEnsoRouter, Token, TokenType } from "../../../src/interfaces/IEnsoRouter.sol";
import { IEnsoWalletV2 } from "../../../src/interfaces/IEnsoWalletV2.sol";
import { IEnsoWalletV2Factory } from "../../../src/interfaces/IEnsoWalletV2Factory.sol";
import { EnsoRouter } from "../../../src/router/EnsoRouter.sol";
import { MockERC721 } from "../../mocks/MockERC721.sol";
import { WeirollPlanner } from "../../utils/WeirollPlanner.sol";
import { Test } from "forge-std/Test.sol";

/// Read-only RPC forks: execute the deployed contracts without replacing their code.
contract NftDeploymentCapabilitiesTest is Test {
    address constant FACTORY = 0xC914A663837Eb21c5a650716E015659686597E55;
    address constant ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;

    function test_ethereumDeployedNftFunding() public {
        _check("ETHEREUM_RPC_URL", 26_234_000, ROUTER);
    }

    function test_optimismDeployedNftFunding() public {
        _check("OPTIMISM_RPC_URL", 158_451_600, ROUTER);
    }

    function test_baseDeployedNftFunding() public {
        _check("BASE_RPC_URL", 52_856_300, ROUTER);
    }

    function test_arbitrumDeployedNftFunding() public {
        _check("ARBITRUM_RPC_URL", 516_606_700, ROUTER);
    }

    function test_avalancheDeployedNftFunding() public {
        _check("AVALANCHE_RPC_URL", 98_060_700, ROUTER);
    }

    function test_robinhoodDeployedNftFunding() public {
        _check("ROBINHOOD_RPC_URL", 93_476_700, 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7);
    }

    /// Blocks are pinned after the NftHelpers deployment (2026-10-20).
    function _check(string memory rpc, uint256 blockNumber, address routerAddress) internal {
        vm.createSelectFork(vm.envString(rpc), blockNumber);
        address executor = address(EnsoRouter(payable(routerAddress)).shortcuts());
        assertGt(executor.code.length, 0);
        IEnsoWalletV2Factory factory = IEnsoWalletV2Factory(FACTORY);
        assertEq(factory.IMPLEMENTATION(), 0xA04df79c7e91f393B64e7BfECbfFA13A9f9F2829);
        _roundTrip(routerAddress, executor, false);
        _roundTrip(FACTORY, factory.getAddress(makeAddr("enso251-deployment-holder")), true);
        _rollback(routerAddress, executor, false);
        _rollback(FACTORY, factory.getAddress(makeAddr("enso251-deployment-rollback")), true);
    }

    function _roundTrip(address funding, address executor, bool wallet) internal {
        address holder = makeAddr("enso251-deployment-holder");
        address receiver = makeAddr("enso251-deployment-receiver");
        MockERC721 nft = new MockERC721("Position", "POS");
        uint256 largeId = (uint256(1) << 128) + 7;
        nft.mint(holder, 0);
        nft.mint(holder, largeId);
        Token[] memory inputs = new Token[](2);
        inputs[0] = Token(TokenType.ERC721, abi.encode(address(nft), uint256(0)));
        inputs[1] = Token(TokenType.ERC721, abi.encode(address(nft), largeId));
        bytes32[] memory commands = new bytes32[](2);
        commands[0] = WeirollPlanner.buildCommand(nft.transferFrom.selector, 0x01, 0x000102ffffff, 0xff, address(nft));
        commands[1] = WeirollPlanner.buildCommand(nft.transferFrom.selector, 0x01, 0x000103ffffff, 0xff, address(nft));
        bytes[] memory state = new bytes[](4);
        state[0] = abi.encode(executor);
        state[1] = abi.encode(receiver);
        state[2] = abi.encode(uint256(0));
        state[3] = abi.encode(largeId);
        bytes memory data =
            abi.encodeWithSelector(IEnsoWalletV2.executeShortcut.selector, bytes32(0), bytes32(0), commands, state);
        vm.startPrank(holder);
        nft.approve(funding, 0);
        nft.approve(funding, largeId);
        if (wallet) {
            (address deployed,) = IEnsoWalletV2Factory(funding).deployAndExecute(inputs, data, new address[](0), false);
            assertEq(deployed, executor);
        } else {
            IEnsoRouter(funding).routeMulti(inputs, data);
        }
        vm.stopPrank();
        assertEq(nft.ownerOf(0), receiver);
        assertEq(nft.ownerOf(largeId), receiver);
        assertEq(nft.balanceOf(executor), 0);
        assertEq(nft.balanceOf(funding), 0);
    }

    function _rollback(address funding, address executor, bool wallet) internal {
        address holder = makeAddr("enso251-deployment-rollback");
        MockERC721 nft = new MockERC721("Position", "POS");
        nft.mint(holder, 7);
        nft.mint(holder, 8);
        Token[] memory inputs = new Token[](2);
        inputs[0] = Token(TokenType.ERC721, abi.encode(address(nft), uint256(7)));
        inputs[1] = Token(TokenType.ERC721, abi.encode(address(nft), uint256(8)));
        vm.startPrank(holder);
        nft.approve(funding, 7);
        vm.expectRevert();
        if (wallet) {
            IEnsoWalletV2Factory(funding).deployAndExecute(inputs, "", new address[](0), false);
        } else {
            IEnsoRouter(funding).routeMulti(inputs, "");
        }
        vm.stopPrank();
        assertEq(nft.ownerOf(7), holder);
        assertEq(nft.ownerOf(8), holder);
        assertEq(nft.balanceOf(executor), 0);
        if (wallet) {
            assertEq(executor.code.length, 0);
        }
    }
}

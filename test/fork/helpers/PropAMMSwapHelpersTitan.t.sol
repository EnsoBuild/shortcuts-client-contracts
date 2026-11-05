// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PropAMMSwapHelpers } from "../../../src/helpers/PropAMMSwapHelpers.sol";
import { IPropAMM } from "../../../src/interfaces/IPropAMM.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Test } from "forge-std/Test.sol";

/// Real pAMM fills: replays a Titan `pamm_quote_stream_v2` frame on a fork.
/// The fixture holds the makers' storage overrides and the pending block they target. Forking the block
/// before it, writing the overrides and moving to the pending block's number and timestamp reproduces
/// the state a taker sees right after the makers' updates in a Titan block.
/// The pinned block is old, so this needs an archive RPC.
contract PropAMMSwapHelpersTitanForkTest is Test {
    struct Store {
        address account;
        bytes32 slot;
        bytes32 value;
    }

    IPoolManager constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V3_USDC_WETH_500 = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // Swap entry points. Metric streams its prices under other addresses than the one it swaps at.
    address constant METRIC = 0x99Ab7c1C5eab47801F7937075998527a550fbA8a;
    address constant BEBOP = 0xB09AAA8933626d7E4C48D65dAd2D77021CFBCA9a;
    address constant FERMI = 0x5979458912F80B96d30D4220af8E2e4925A33320;

    uint256 constant AMOUNT_IN = 1 ether;

    PropAMMSwapHelpers helper;
    address receiver = makeAddr("receiver");

    function setUp() public {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/test/fixtures/titan/pamm-overrides.json"));
        uint256 pendingBlock = vm.parseJsonUint(json, ".blockNumber");

        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"), pendingBlock - 1);

        Store[] memory stores = abi.decode(vm.parseJson(json, ".stores"), (Store[]));
        for (uint256 i; i < stores.length; ++i) {
            vm.store(stores[i].account, stores[i].slot, stores[i].value);
        }
        vm.roll(pendingBlock);
        vm.warp(vm.parseJsonUint(json, ".timestamp"));

        helper = new PropAMMSwapHelpers(POOL_MANAGER);
        deal(WETH, address(this), AMOUNT_IN);
        IERC20(WETH).approve(address(helper), AMOUNT_IN);
    }

    function test_metric_fills() public {
        _assertPammFills(METRIC);
    }

    function test_bebop_fills() public {
        _assertPammFills(BEBOP);
    }

    function test_fermi_fills() public {
        _assertPammFills(FERMI);
    }

    /// The pAMM quotes at this snapshot, so the helper must route to it and pay out its quote.
    function _assertPammFills(address pamm) internal {
        bytes memory fallbackData = abi.encode(UNISWAP_V3_USDC_WETH_500);
        uint256 pammQuote = IPropAMM(pamm).quote(WETH, USDC, AMOUNT_IN);
        assertGt(pammQuote, 0, "pAMM does not quote at this snapshot");

        vm.expectEmit(address(helper));
        emit PropAMMSwapHelpers.PropAMMSwap(
            pamm,
            WETH,
            USDC,
            AMOUNT_IN,
            pammQuote,
            receiver,
            PropAMMSwapHelpers.Outcome.PropAMMFilled,
            PropAMMSwapHelpers.FallbackProtocol.UniswapV3
        );
        uint256 amountOut = helper.swap(
            pamm, WETH, USDC, AMOUNT_IN, 0, receiver, PropAMMSwapHelpers.FallbackProtocol.UniswapV3, fallbackData
        );
        assertEq(amountOut, pammQuote, "pAMM paid a different amount than it quoted");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/helpers/MaverickV2Helpers.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract MaverickV2HelpersTest is Test {
    MaverickV2Helpers public maverickHelpers;
    address public yap = 0x5649009D65EbC80eFEe715c95768607B8fbAcd55;
    address public lens = 0xBf0D89E67351f68a0a921943332c5bE0f7a0FF8A;

    string _rpcURL = vm.envString("PLUME_RPC_URL");
    uint256 _plumeFork;

    uint256 public constant AMOUNT = 10 ** 18;

    function setUp() public {
        _plumeFork = vm.createFork(_rpcURL);
        vm.selectFork(_plumeFork);
        maverickHelpers = new MaverickV2Helpers();
    }

    function testEncode() public {
        bytes memory callData =
            maverickHelpers.encodeAddLiquidityAndMintBoostedPosition(AMOUNT, yap, lens, address(this));
        assertEq(bytes4(callData), IMaverickV2LiquidityManager.addLiquidityAndMintBoostedPosition.selector);
        console.logBytes(callData);
    }
}

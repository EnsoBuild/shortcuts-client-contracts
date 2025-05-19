// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../src/helpers/MaverickV2Helpers.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract MaverickV2HelpersTest is Test {
    MaverickV2Helpers public maverickHelpers;
    address public yap = 0x5649009D65EbC80eFEe715c95768607B8fbAcd55;
    IERC20 public usdce = IERC20(0x78adD880A697070c1e765Ac44D65323a0DcCE913);
    IERC20 public pusd = IERC20(0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F);
    address public manager = 0xc66e75Fa945fcBdF10f966faa37185204D849BF4;
    address public lens = 0xBf0D89E67351f68a0a921943332c5bE0f7a0FF8A;
    address public refund = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

    address public usdce_holder = 0x329C395D83493ea909ba3CE76b04766E17De4Ea8;
    address public pusd_holder = 0x8e87Caf1FC5a0d4aebe0E0c976b24a3A9e3672C4;

    string _rpcURL = vm.envString("PLUME_RPC_URL");
    uint256 _plumeFork;

    uint256 public constant USDCE_AMOUNT = 10 ** 9;
    uint256 public constant PUSD_AMOUNT = 10 ** 9;

    function setUp() public {
        _plumeFork = vm.createFork(_rpcURL);
        vm.selectFork(_plumeFork);
        maverickHelpers = new MaverickV2Helpers();
        vm.startPrank(usdce_holder);
        usdce.transfer(address(this), USDCE_AMOUNT);
        vm.stopPrank();
        vm.startPrank(pusd_holder);
        pusd.transfer(address(this), PUSD_AMOUNT);
        vm.stopPrank();
    }

    function testEncode() public {
        uint256 usdceRefundBalanceBefore = usdce.balanceOf(refund);
        uint256 pusdRefundBalanceBefore = pusd.balanceOf(refund);

        usdce.approve(address(maverickHelpers), USDCE_AMOUNT);
        pusd.approve(address(maverickHelpers), PUSD_AMOUNT);
        maverickHelpers.addLiquidityAndMintBoostedPosition(
            USDCE_AMOUNT,
            PUSD_AMOUNT,
            usdce,
            pusd,
            true,
            100,
            yap,
            manager,
            lens,
            address(this),
            refund
        );
        // assert that the test address received yap
        assertGt(IERC20(yap).balanceOf(address(this)), 0);
        // assert funds are not left on maverickHelpers
        assertEq(usdce.balanceOf(address(maverickHelpers)), 0);
        assertEq(pusd.balanceOf(address(maverickHelpers)), 0);
        // assert funds were sent to refund address
        uint256 usdceRefundBalanceAfter = usdce.balanceOf(refund);
        uint256 pusdRefundBalanceAfter = pusd.balanceOf(refund);
        assertGe(usdceRefundBalanceAfter - usdceRefundBalanceBefore, 0);
        assertGe(pusdRefundBalanceAfter - pusdRefundBalanceBefore, 0);
    }
}
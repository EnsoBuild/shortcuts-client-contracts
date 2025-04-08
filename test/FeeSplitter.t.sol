// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { FeeSplitter } from "../src/helpers/FeeSplitter.sol";

import { DeployerResult, DeployerTest } from "../script/FeeSplitterDeployerTest.s.sol";

contract FeeSplitterTest is Test {
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant ipor = IERC20(0x1e4746dC744503b53b4A082cB3607B169a289090);

    FeeSplitter internal feeSplitter;

    address internal owner;
    address internal attacker;

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        vm.createSelectFork("mainnet");

        (, uint256 deployerKey) = makeAddrAndKey("deployer");
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));

        owner = makeAddr("owner");
        vm.setEnv("OWNER", vm.toString(owner));

        attacker = makeAddr("attacker");

        DeployerResult memory result = new DeployerTest().run();

        feeSplitter = result.feeSplitter;
    }

    function testOnlyOwnerCanChangeRecipients() public {
        address[] memory recipients = new address[](1);
        recipients[0] = attacker;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 1;

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, attacker));
        feeSplitter.setRecipients(recipients, shares);

        vm.prank(owner);
        feeSplitter.setRecipients(recipients, shares);

        assertEq(feeSplitter.recipients(0), attacker);
        assertEq(feeSplitter.shares(0), 1);
    }

    function testCanClaimEth() public {
        assertEq(address(feeSplitter).balance, 0);

        deal(address(feeSplitter), 100);
        assertEq(address(feeSplitter).balance, 100);

        uint256 recipient0BalanceBefore = feeSplitter.recipients(0).balance;
        uint256 recipient1BalanceBefore = feeSplitter.recipients(1).balance;

        feeSplitter.claim();

        assertEq(address(feeSplitter).balance, 0);
        assertEq(feeSplitter.recipients(0).balance, recipient0BalanceBefore + 50);
        assertEq(feeSplitter.recipients(1).balance, recipient1BalanceBefore + 50);

        // claim again but balances should not change
        feeSplitter.claim();

        assertEq(address(feeSplitter).balance, 0);
        assertEq(address(feeSplitter.recipients(0)).balance, recipient0BalanceBefore + 50);
        assertEq(address(feeSplitter.recipients(1)).balance, recipient1BalanceBefore + 50);
    }

    function testCanClaimERC20() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = usdc;

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);

        deal(address(usdc), address(feeSplitter), 1000e6);
        assertEq(usdc.balanceOf(address(feeSplitter)), 1000e6);

        uint256 recipient0BalanceBefore = usdc.balanceOf(feeSplitter.recipients(0));
        uint256 recipient1BalanceBefore = usdc.balanceOf(feeSplitter.recipients(1));

        feeSplitter.claimERC20(tokens);

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(usdc.balanceOf(feeSplitter.recipients(0)), recipient0BalanceBefore + 500e6);
        assertEq(usdc.balanceOf(feeSplitter.recipients(1)), recipient1BalanceBefore + 500e6);

        // claim again but balances should not change
        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.NoBalance.selector, usdc));
        feeSplitter.claimERC20(tokens);

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(usdc.balanceOf(feeSplitter.recipients(0)), recipient0BalanceBefore + 500e6);
        assertEq(usdc.balanceOf(feeSplitter.recipients(1)), recipient1BalanceBefore + 500e6);
    }

    function testCanClaimMultipleERC20() public {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = usdc;
        tokens[1] = ipor;

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(ipor.balanceOf(address(feeSplitter)), 0);

        deal(address(usdc), address(feeSplitter), 1000e6);
        deal(address(ipor), address(feeSplitter), 1 ether);
        assertEq(usdc.balanceOf(address(feeSplitter)), 1000e6);
        assertEq(ipor.balanceOf(address(feeSplitter)), 1 ether);

        uint256 recipient0USDCBalanceBefore = usdc.balanceOf(feeSplitter.recipients(0));
        uint256 recipient1USDCBalanceBefore = usdc.balanceOf(feeSplitter.recipients(1));
        uint256 recipient0IPORBalanceBefore = ipor.balanceOf(feeSplitter.recipients(0));
        uint256 recipient1IPORBalanceBefore = ipor.balanceOf(feeSplitter.recipients(1));

        feeSplitter.claimERC20(tokens);

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(ipor.balanceOf(address(feeSplitter)), 0);

        assertEq(usdc.balanceOf(feeSplitter.recipients(0)), recipient0USDCBalanceBefore + 500e6);
        assertEq(usdc.balanceOf(feeSplitter.recipients(1)), recipient1USDCBalanceBefore + 500e6);
        assertEq(ipor.balanceOf(feeSplitter.recipients(0)), recipient0IPORBalanceBefore + 0.5 ether);
        assertEq(ipor.balanceOf(feeSplitter.recipients(1)), recipient1IPORBalanceBefore + 0.5 ether);
    }

    function testUnequalShares() public {
        address[] memory recipients = new address[](2);
        recipients[0] = 0xB7bE82790d40258Fd028BEeF2f2007DC044F3459; // ipor multisig
        recipients[1] = 0x2C0b46F1276A93B458346e53f6B7B57Aba20D7D1; // enso multisig

        uint16[] memory shares = new uint16[](2);
        shares[0] = 9;
        shares[1] = 1;

        vm.prank(owner);
        feeSplitter.setRecipients(recipients, shares);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = usdc;
        tokens[1] = ipor;

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(ipor.balanceOf(address(feeSplitter)), 0);

        deal(address(usdc), address(feeSplitter), 1000e6);
        deal(address(ipor), address(feeSplitter), 1 ether);
        assertEq(usdc.balanceOf(address(feeSplitter)), 1000e6);
        assertEq(ipor.balanceOf(address(feeSplitter)), 1 ether);

        uint256 recipient0USDCBalanceBefore = usdc.balanceOf(feeSplitter.recipients(0));
        uint256 recipient1USDCBalanceBefore = usdc.balanceOf(feeSplitter.recipients(1));
        uint256 recipient0IPORBalanceBefore = ipor.balanceOf(feeSplitter.recipients(0));
        uint256 recipient1IPORBalanceBefore = ipor.balanceOf(feeSplitter.recipients(1));

        feeSplitter.claimERC20(tokens);

        assertEq(usdc.balanceOf(address(feeSplitter)), 0);
        assertEq(ipor.balanceOf(address(feeSplitter)), 0);

        assertEq(usdc.balanceOf(feeSplitter.recipients(0)), recipient0USDCBalanceBefore + 900e6);
        assertEq(usdc.balanceOf(feeSplitter.recipients(1)), recipient1USDCBalanceBefore + 100e6);
        assertEq(ipor.balanceOf(feeSplitter.recipients(0)), recipient0IPORBalanceBefore + 0.9 ether);
        assertEq(ipor.balanceOf(feeSplitter.recipients(1)), recipient1IPORBalanceBefore + 0.1 ether);
    }
}

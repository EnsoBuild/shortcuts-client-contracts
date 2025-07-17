// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../src/factory/ERC4337CloneFactory.sol";
import { IERC4337CloneInitializer } from "../src/factory/interfaces/IERC4337CloneInitializer.sol";
import { TestPaymaster } from "./mocks/TestPaymaster.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";

import { SIG_VALIDATION_SUCCESS } from "account-abstraction/core/Helpers.sol";
import { IAccount, PackedUserOperation } from "account-abstraction/interfaces/IAccount.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import { StdStorage, Test, console2, stdStorage } from "forge-std-1.9.7/Test.sol";
// EnsoReceiver.sol -> IAccount
// ERC4337CloneFactory.sol -> IAccount deployer
// SignaturePaymaster.sol -> IPaymaster
// TestPaymaster.sol -> permisive SignaturePaymaster.sol (mock)
// EntryPoint missing 0x4337084d9e255ff0702461cf8895ce9e3b5ff108

contract AlphaShortcutsTest is Test {
    using SafeERC20 for IERC20;

    IERC20 private constant NATIVE_ASSET = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address private constant ENSO_ACCOUNT = 0x93621DCA56fE26Cdee86e4F6B18E116e9758Ff11;
    address private constant ENSO_DEPLOYER = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA;
    address payable private constant ENTRY_POINT_0_8 = payable(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);
    address payable private constant SIGNER = payable(0xE150e171dDf7ef6785e2c6fBBbE9eCd0f2f63682);
    bytes32 private constant SIGNER_PK = 0x74dc97524c0473f102953ebfe8bbec30f0e9cd304703ed7275c708921deaab3b;

    address payable private s_deployer;
    address payable private s_bundler;
    EntryPoint private s_entryPoint;
    TestPaymaster private s_paymaster;
    EnsoReceiver private s_accountImpl;
    ERC4337CloneFactory private s_accountFactory;

    function setUp() public {
        // Fork mainnet
        string memory rpcUrl = vm.envString("ETHEREUM_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Roles
        vm.deal(SIGNER, 1000 ether);
        vm.label(SIGNER, "Signer");
        vm.deal(ENSO_DEPLOYER, 1000 ether);
        vm.label(ENSO_DEPLOYER, "EnsoDeployer");

        s_deployer = payable(address(0));
        vm.deal(s_deployer, 1000 ether);

        s_bundler = payable(address(1));
        vm.deal(s_bundler, 1000 ether);
        vm.label(s_bundler, "Bundler");

        s_entryPoint = EntryPoint(ENTRY_POINT_0_8);

        // Deploy & set up TestPaymaster
        // Deploy & set up ERC4337CloneFactory
        // Deploy & SetUp EnsoReceiver (native token)
        // Set up EntryPoint v0.8?
        // Prepare userOp
        // - Get shortcut encoded to be executed in EnsoReceiver.safeExecute()

        // Deploy & set up TestPaymaster
        vm.startPrank(s_deployer);
        s_paymaster = new TestPaymaster(IEntryPoint(ENTRY_POINT_0_8));
        vm.label(address(s_paymaster), "TestPaymaster");
        s_paymaster.addDeposit{ value: 10 ether }();
        vm.stopPrank();

        // Deploy EnsoReceiver
        vm.prank(s_deployer);
        s_accountImpl = new EnsoReceiver{ salt: "EnsoReceiver" }();
        vm.label(address(s_accountImpl), "EnsoReceiver Implementation");

        // Deploy & set up ERC4337CloneFactory
        vm.startPrank(ENSO_DEPLOYER);
        s_accountFactory =
            new ERC4337CloneFactory{ salt: "ERC4337CloneFactory" }(address(s_accountImpl), ENTRY_POINT_0_8);
        vm.label(address(s_accountFactory), "ERC4337CloneFactory");
        vm.stopPrank();
    }

    // NOTE: context:
    // - Sender is EOA.
    // - Account manually deployed.
    // - TestPaymaster is lax.
    function test_execution() public {
        PackedUserOperation memory userOp;

        // Deploy & set up EnsoReceiver, and fund it with 1 ETH
        vm.prank(s_deployer);
        address payable account = payable(s_accountFactory.deploy(SIGNER)); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        vm.label(account, "EnsoReceiver"); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        userOp.sender = account;

        vm.prank(SIGNER);
        (bool success,) = account.call{ value: 1 ether }("");
        (success); // shh

        // NOTE: from EnsoReceiver address to receiver address (SIGNER), 1 ETH to 1 WETH via `delegate` strategy
        bytes memory shortcutCalldata =
            hex"95352c9fad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a56c2e2f1e3b4d48a5be640d785eba608130313233343536373839414243444546000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000004d0e30db00300ffffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a9059cbb010100ffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc26e7a43a3010002ffffffff027e7d64d987cab6eed08a191c4c2459daf2f8ed0b241c59120102ffffffffffff7e7d64d987cab6eed08a191c4c2459daf2f8ed0b0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000e150e171ddf7ef6785e2c6fbbbe9ecd0f2f6368200000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000dcef33a6f838000";

        vm.prank(SIGNER);
        (bool success2,) = account.call{ value: 1 ether }(shortcutCalldata);
        assertEq(success2, true);

        // TODO VN: `.getAddress()` or `EntryPoint.getSenderAddress()`?
        address accountExpected = s_accountFactory.getAddress(SIGNER);
        assertEq(accountExpected, account);
        //
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(accountExpected, laneId);
        userOp.nonce = nonce;

        bytes memory initCode = "";
        userOp.initCode = initCode;

        bytes memory callData = abi.encodeCall(EnsoReceiver.safeExecute, (NATIVE_ASSET, 1 ether, shortcutCalldata));
        userOp.callData = callData;

        uint256 routerCalldataGas = 100_000; // 95_820;
        uint256 verificationGasLimit = 40_000;
        bytes32 accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(routerCalldataGas));
        userOp.accountGasLimits = accountGasLimits;

        userOp.gasFees = _gasFees();

        uint128 paymasterVerificationGas = 11_000; // TODO: fails at 10_000, not sure how its calculated
        uint128 paymasterPostOp = 0;
        bytes memory paymasterAndData =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp);
        userOp.paymasterAndData = paymasterAndData;

        // (
        //     uint256 preOpGas,
        //     uint256 prefund,
        //     uint256 accountValidationData,
        //     uint256 paymasterValidationData,
        //     bytes memory paymasterContext
        // ) = validationResult.returnInfo;

        uint256 preVerificationGas = 100_000;
        userOp.preVerificationGas = preVerificationGas;

        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(SIGNER_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        // STEP 1 handleUserOp: validateUserOp
        vm.prank(address(s_entryPoint));
        uint256 gasPreValidateUserOp = gasleft();
        uint256 validationData = EnsoReceiver(account).validateUserOp(userOp, userOpHash, 0);
        uint256 gasPostValidateUserOp = gasleft();
        console2.log("*** validateUserOp gas", gasPreValidateUserOp - gasPostValidateUserOp);
        assertEq(validationData, SIG_VALIDATION_SUCCESS);

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        uint256 balancePreSignerWeth = WETH.balanceOf(SIGNER);

        s_entryPoint.handleOps(userOps, s_bundler);

        uint256 balancePostSignerWeth = WETH.balanceOf(SIGNER);

        uint256 balanceDiffSignerWeth = balancePostSignerWeth - balancePreSignerWeth;
        assertEq(balanceDiffSignerWeth, 1 ether);

        // Bundler -> EntryPoint.handleOps
        //  - EnsoReceiver.validateUserOp()
        //  - TestPaymaster.validatePaymasterUserOp()
        //  - EnsoReceiver.safeExecute()
        //  - TestPaymaster.postOp
    }

    function test_init() public {
        PackedUserOperation memory userOp;

        // Get address
        address payable account = payable(s_accountFactory.getAddress(SIGNER)); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        vm.label(account, "EnsoReceiver"); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        userOp.sender = account;

        // Fund account before deployment
        vm.prank(SIGNER);
        (bool success,) = account.call{ value: 1 ether }("");
        (success); // shh

        // Setup initCode
        userOp.initCode = _initCode(SIGNER);

        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        bytes memory shortcutCalldata =
            hex"95352c9fad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a56c2e2f1e3b4d48a5be640d785eba608130313233343536373839414243444546000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000004d0e30db00300ffffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a9059cbb010100ffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc26e7a43a3010002ffffffff027e7d64d987cab6eed08a191c4c2459daf2f8ed0b241c59120102ffffffffffff7e7d64d987cab6eed08a191c4c2459daf2f8ed0b0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000e150e171ddf7ef6785e2c6fbbbe9ecd0f2f6368200000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000dcef33a6f838000";
        bytes memory callData = abi.encodeCall(EnsoReceiver.safeExecute, (NATIVE_ASSET, 1 ether, shortcutCalldata));
        userOp.callData = callData;

        uint256 routerCalldataGas = 100_000; // 95_820;
        uint256 verificationGasLimit = 200_000; // verifcation gas limit includes deployment costs
        bytes32 accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(routerCalldataGas));
        userOp.accountGasLimits = accountGasLimits;

        userOp.gasFees = _gasFees();

        uint128 paymasterVerificationGas = 11_000; // TODO: fails at 10_000, not sure how its calculated
        uint128 paymasterPostOp = 0;
        bytes memory paymasterAndData =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp);
        userOp.paymasterAndData = paymasterAndData;

        // (
        //     uint256 preOpGas,
        //     uint256 prefund,
        //     uint256 accountValidationData,
        //     uint256 paymasterValidationData,
        //     bytes memory paymasterContext
        // ) = validationResult.returnInfo;

        uint256 preVerificationGas = 100_000;
        userOp.preVerificationGas = preVerificationGas;

        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(SIGNER_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        uint256 balancePreSignerWeth = WETH.balanceOf(SIGNER);

        s_entryPoint.handleOps(userOps, s_bundler);

        uint256 balancePostSignerWeth = WETH.balanceOf(SIGNER);

        uint256 balanceDiffSignerWeth = balancePostSignerWeth - balancePreSignerWeth;
        assertEq(balanceDiffSignerWeth, 1 ether);

        // Bundler -> EntryPoint.handleOps
        //  - EnsoReceiver.validateUserOp()
        //  - TestPaymaster.validatePaymasterUserOp()
        //  - EnsoReceiver.safeExecute()
        //  - TestPaymaster.postOp
    }

    function test_failing_shortcut_eth_refund() public {
        PackedUserOperation memory userOp;

        // Get address
        address payable account = payable(s_accountFactory.getAddress(SIGNER)); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        vm.label(account, "EnsoReceiver"); // 0x0905ab61D02f48bC4736e1fE5eaFA86557aA37F1
        userOp.sender = account;

        // Fund account before deployment
        vm.prank(SIGNER);
        (bool success,) = account.call{ value: 1 ether }("");
        (success); // shh

        // Setup initCode
        userOp.initCode = _initCode(SIGNER);

        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // failing shortcut uses a minAmountOut of 10**18 + 1
        bytes memory failingShortcutCalldata =
            hex"95352c9fad7c5bef027816a800da1736444fb58a807ef4c9603b7848673f7e3a68eb14a56c2e2f1e3b4d48a5be640d785eba608130313233343536373839414243444546000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000004d0e30db00300ffffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a9059cbb010100ffffffffffc02aaa39b223fe8d0a0e5c4f27ead9083c756cc26e7a43a3010002ffffffff027e7d64d987cab6eed08a191c4c2459daf2f8ed0b241c59120102ffffffffffff7e7d64d987cab6eed08a191c4c2459daf2f8ed0b0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000e150e171ddf7ef6785e2c6fbbbe9ecd0f2f6368200000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000DE0B6B3A7640001";
        bytes memory callData =
            abi.encodeCall(EnsoReceiver.safeExecute, (NATIVE_ASSET, 1 ether, failingShortcutCalldata));
        userOp.callData = callData;

        uint256 routerCalldataGas = 100_000; // 95_820;
        uint256 verificationGasLimit = 200_000; // verifcation gas limit includes deployment costs
        bytes32 accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(routerCalldataGas));
        userOp.accountGasLimits = accountGasLimits;

        userOp.gasFees = _gasFees();

        uint128 paymasterVerificationGas = 11_000; // TODO: fails at 10_000, not sure how its calculated
        uint128 paymasterPostOp = 0;
        bytes memory paymasterAndData =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp);
        userOp.paymasterAndData = paymasterAndData;

        // (
        //     uint256 preOpGas,
        //     uint256 prefund,
        //     uint256 accountValidationData,
        //     uint256 paymasterValidationData,
        //     bytes memory paymasterContext
        // ) = validationResult.returnInfo;

        uint256 preVerificationGas = 100_000;
        userOp.preVerificationGas = preVerificationGas;

        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(SIGNER_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // since this shortcut should fail, the eth deposited should be transferred back to signer
        uint256 balancePreSignerEth = SIGNER.balance;

        s_entryPoint.handleOps(userOps, s_bundler);

        uint256 balancePostSignerEth = SIGNER.balance;

        uint256 balanceDiffSignerEth = balancePostSignerEth - balancePreSignerEth;
        assertEq(balanceDiffSignerEth, 1 ether);

        // Bundler -> EntryPoint.handleOps
        //  - EnsoReceiver.validateUserOp()
        //  - TestPaymaster.validatePaymasterUserOp()
        //  - EnsoReceiver.safeExecute()
        //  - TestPaymaster.postOp
    }

    function _initCode(address signer) internal view returns (bytes memory initCode) {
        bytes memory initCalldata = abi.encodeWithSelector(s_accountFactory.deploy.selector, signer);
        initCode = abi.encodePacked(address(s_accountFactory), initCalldata);
    }

    function _gasFees() internal view returns (bytes32 gasFees) {
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = uint128(block.basefee) + maxPriorityFeePerGas;
        gasFees = bytes32((uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas));
    }
}

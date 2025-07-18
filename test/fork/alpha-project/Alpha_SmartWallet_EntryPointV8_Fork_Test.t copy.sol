// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../../../src/factory/ERC4337CloneFactory.sol";
import { SignaturePaymaster } from "../../../src/paymaster/SignaturePaymaster.sol";
import { Shortcut } from "../../shortcuts/ShortcutDataTypes.sol";
import { ShortcutsEthereum } from "../../shortcuts/ShortcutsEthereum.sol";
import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";
import { IEntryPoint, PackedUserOperation } from "account-abstraction/interfaces/IEntryPoint.sol";
import { StdStorage, Test, console2, stdStorage } from "forge-std-1.9.7/Test.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {
    AdvancedSafeInitParams,
    DeployedSafe,
    SafeInstance,
    SafeTestLib,
    SafeTestTools
} from "safe-tools-0.2.0/SafeTestTools.sol";

contract Alpha_SmartWallet_EntryPointV8_Fork_Test is Test {
    using SafeERC20 for IERC20;

    address private constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address payable private constant ENSO_ACCOUNT = payable(0x93621DCA56fE26Cdee86e4F6B18E116e9758Ff11);
    address payable private constant ENSO_DEPLOYER = payable(0x826e0BB2276271eFdF2a500597f37b94f6c153bA);
    address payable private constant ENSO_FEE_RECEIVER = payable(0x6AA68C46eD86161eB318b1396F7b79E386e88676);

    address payable private constant ENTRY_POINT_0_8 = payable(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    address payable private constant ENSO_BACKEND = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // Anvil 0
    bytes32 private constant ENSO_BACKEND_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address payable private constant EOA_1 = payable(0xE150e171dDf7ef6785e2c6fBBbE9eCd0f2f63682);
    bytes32 private constant EOA_1_PK = 0x74dc97524c0473f102953ebfe8bbec30f0e9cd304703ed7275c708921deaab3b;
    address payable private constant EOA_2 = payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8); // Anvil 1
    bytes32 private constant EOA_2_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address payable private constant BUNDLER_1 = payable(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720); // Anvil 9
    bytes32 private constant BUNDLER_1_PK = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;

    uint256 private s_blockNumber;
    EntryPoint private s_entryPoint;
    SignaturePaymaster private s_paymaster;
    EnsoReceiver private s_accountImpl;
    ERC4337CloneFactory private s_accountFactory;

    function setUp() public {
        // Fork mainnet
        s_blockNumber = 22_932_038;
        string memory rpcUrl = vm.envString("ETHEREUM_RPC_URL");
        vm.createSelectFork(rpcUrl, s_blockNumber);

        // Roles
        vm.label(address(WETH), "WETH9");
        vm.label(ENSO_ACCOUNT, "ENSO_ACCOUNT");
        vm.label(ENSO_DEPLOYER, "ENSO_DEPLOYER");
        vm.label(ENSO_FEE_RECEIVER, "ENSO_FEE_RECEIVER");
        vm.label(ENTRY_POINT_0_8, "EntryPoint_0_8");

        vm.label(ENSO_BACKEND, "ENSO_BACKEND");
        vm.label(EOA_1, "EOA_1");
        vm.label(EOA_2, "EOA_2");
        vm.label(BUNDLER_1, "BUNDLER_1");

        // NOTE: these addresses may not be funded in a fork
        vm.deal(ENSO_DEPLOYER, 1000 ether);
        vm.deal(EOA_1, 1000 ether);
        vm.deal(EOA_2, 1000 ether);
        vm.deal(BUNDLER_1, 1000 ether);

        s_entryPoint = EntryPoint(ENTRY_POINT_0_8);

        // Deploy SignaturePaymaster
        vm.startPrank(ENSO_DEPLOYER);
        s_paymaster = new SignaturePaymaster(IEntryPoint(ENTRY_POINT_0_8), ENSO_DEPLOYER);
        vm.label(address(s_paymaster), "SignaturePaymaster");
        s_paymaster.deposit{ value: 10 ether }();
        s_paymaster.setSigner(ENSO_BACKEND, true);
        vm.stopPrank();

        // Deploy EnsoReceiver implementation
        vm.prank(ENSO_DEPLOYER);
        s_accountImpl = new EnsoReceiver{ salt: "EnsoReceiver" }();
        vm.label(address(s_accountImpl), "EnsoReceiver_Impl");

        // Deploy ERC4337CloneFactory
        vm.startPrank(ENSO_DEPLOYER);
        s_accountFactory =
            new ERC4337CloneFactory{ salt: "ERC4337CloneFactory" }(address(s_accountImpl), ENTRY_POINT_0_8);
        vm.label(address(s_accountFactory), "ERC4337CloneFactory");
        vm.stopPrank();
    }

    /**
     * @dev Should successfully execute the shortcut as expected:
     * - Caller is an EOA.
     * - EnsoReceiver wraps 1 ETH (minus 0.01 ETH fees) as WETH, and sends them to EOA_1 (+0.99 WETH).
     * - EnsoReceiver sends 0.01 ETH to fee receiver as part of the shortcut.
     * - EntryPoint subtracts the execution cost from SignaturePaymaster balances.
     * - Bundler execution costs are refunded.
     */
    function test_successful_shortcut() public {
        // *** Arrange ***
        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1();

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(EOA_1));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(EOA_1);
        (bool success,) = account.call{ value: shortcut.amountsIn[0] }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(EOA_1);

        // UserOp.nonce - Get nonce for the account
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // UserOp.callData - Encode the call to `EnsoReceiver.safeExecute`
        bytes memory callData = abi.encodeCall(
            EnsoReceiver.safeExecute, (IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData)
        );
        userOp.callData = callData;

        // UserOp.accountGasLimits
        uint256 verificationGasLimit = 200_000;
        userOp.accountGasLimits = _accountGasLimits(shortcut.txGas, verificationGasLimit);

        // UserOp.gasFees
        userOp.gasFees = _gasFees();

        // UserOp.preVerificationGas
        userOp.preVerificationGas = 100_000;

        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp + 5 seconds);
        uint48 validAfter = uint48(block.timestamp - 5 seconds);
        uint128 paymasterVerificationGas = 100_000;
        uint128 paymasterPostOp = 100_000;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter);
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with ENSO_BACKEND's private key
        bytes32 pmdHash = s_paymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(ENSO_BACKEND_PK), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;

        // UserOp.signature - Sign the userOpHash with EOA_1's private key
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(EOA_1_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // --- Get balances before execution ---
        uint256 balancePreReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePreReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePreFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePreFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePreEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePreEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePrePaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePrePaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePreEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePreEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePreEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePreBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePreBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        // *** Act & Assert ***
        vm.prank(BUNDLER_1);
        vm.expectEmit(address(account));
        emit EnsoReceiver.ShortcutExecutionSuccessful();
        s_entryPoint.handleOps(userOps, BUNDLER_1);

        // --- Get balances after execution ---
        uint256 balancePostReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePostReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePostFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePostFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePostEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePostEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePostPaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePostPaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePostEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePostEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePostEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePostBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePostBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        // Assert balances
        _assertBalanceDiff(balancePreReceiverTokenIn, balancePostReceiverTokenIn, 0, "Receiver TokenIn (ETH)");
        _assertBalanceDiff(
            balancePreReceiverTokenOut,
            balancePostReceiverTokenOut,
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver TokenOut (WETH)"
        );

        _assertBalanceDiff(
            balancePreFeeReceiverTokenIn,
            balancePostFeeReceiverTokenIn,
            int256(shortcut.fee),
            "FeeReceiver TokenIn (ETH)"
        );
        _assertBalanceDiff(
            balancePreFeeReceiverTokenOut, balancePostFeeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenIn,
            balancePostEnsoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenOut, balancePostEnsoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(balancePrePaymasterTokenIn, balancePostPaymasterTokenIn, 0, "Paymaster TokenIn (ETH)");
        _assertBalanceDiff(balancePrePaymasterTokenOut, balancePostPaymasterTokenOut, 0, "Paymaster TokenOut (WETH)");

        _assertBalanceDiff(
            balancePreEntryPointPaymaster,
            balancePostEntryPointPaymaster,
            -2_007_367_757_400_798,
            "EntryPoint Paymaster balance (ETH)"
        );
        _assertBalanceDiff(
            balancePreEntryPointTokenIn,
            balancePostEntryPointTokenIn,
            -2_007_367_757_400_798,
            "EntryPoint TokenIn (ETH)"
        );
        _assertBalanceDiff(balancePreEntryPointTokenOut, balancePostEntryPointTokenOut, 0, "EntryPoint TokenOut (WETH)");

        _assertBalanceDiff(balancePreBundler1TokenIn, balancePostBundler1TokenIn, 0, "Bundler1 TokenIn (ETH)");
        _assertBalanceDiff(balancePreBundler1TokenOut, balancePostBundler1TokenOut, 0, "Bundler1 TokenOut (WETH)");
    }

    /**
     * @dev Should successfully execute the shortcut as expected:
     * - Caller is an ERC1271 compatible Smart Wallet (GnosisSafe v1.3.0).
     * - EnsoReceiver wraps 1 ETH (minus 0.01 ETH fees) as WETH, and sends them to EOA_1 (+0.99 WETH).
     * - EnsoReceiver sends 0.01 ETH to fee receiver as part of the shortcut.
     * - EntryPoint subtracts the execution cost from SignaturePaymaster balances.
     * - Bundler execution costs are refunded.
     */
    function test_successful_shortcut_smart_wallet() public {
        vm.skip(true); // NOTE: use Safe.sol instead of safe-tools-0.2.0.

        // *** Arrange ***
        // --- Smart Wallet ---
        SafeTestTools safeTestTools = new SafeTestTools();
        uint256[] memory ownerPKs = new uint256[](2);
        ownerPKs[0] = uint256(EOA_1_PK);
        ownerPKs[1] = uint256(EOA_2_PK);
        uint256 threshold = 2;
        uint256 initialBalance = 1 ether;
        AdvancedSafeInitParams memory advancedParams;
        SafeInstance memory safeInstance = safeTestTools._setupSafe(ownerPKs, threshold, initialBalance, advancedParams);
        DeployedSafe gnosisSafe = safeInstance.safe;
        vm.label(address(gnosisSafe), "GnosisSafe_1_3_0");

        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1();
        shortcut.receiver = address(gnosisSafe); // NOTE: override receiver to smart wallet

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(address(gnosisSafe)));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(address(gnosisSafe));
        (bool success,) = account.call{ value: shortcut.amountsIn[0] }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(address(gnosisSafe));

        // UserOp.nonce - Get nonce for the account
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // UserOp.callData - Encode the call to `EnsoReceiver.safeExecute`
        bytes memory callData = abi.encodeCall(
            EnsoReceiver.safeExecute, (IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData)
        );
        userOp.callData = callData;

        // UserOp.accountGasLimits
        uint256 verificationGasLimit = 200_000;
        userOp.accountGasLimits = _accountGasLimits(shortcut.txGas, verificationGasLimit);

        // UserOp.gasFees
        userOp.gasFees = _gasFees();

        // UserOp.preVerificationGas
        userOp.preVerificationGas = 100_000;

        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp + 5 seconds);
        uint48 validAfter = uint48(block.timestamp - 5 seconds);
        uint128 paymasterVerificationGas = 100_000;
        uint128 paymasterPostOp = 100_000;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter);
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with ENSO_BACKEND's private key
        bytes32 pmdHash = s_paymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(ENSO_BACKEND_PK), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;

        // TODO VN: start
        // UserOp.signature - Sign the userOpHash with Smart Wallet
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(uint256(EOA_1_PK), userOpHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(uint256(EOA_2_PK), userOpHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        bytes memory multiSignature = bytes.concat(signature1, signature2);

        SafeTestLib.EIP1271Sign(safeInstance, multiSignature);
        userOp.signature = multiSignature;
        // TODO VN: end

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // --- Get balances before execution ---
        uint256 balancePreReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePreReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePreFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePreFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePreEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePreEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePrePaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePrePaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePreEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePreEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePreEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePreBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePreBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        // *** Act & Assert ***
        vm.prank(BUNDLER_1);
        vm.expectEmit(address(account));
        emit EnsoReceiver.ShortcutExecutionSuccessful();
        s_entryPoint.handleOps(userOps, BUNDLER_1);

        // --- Get balances after execution ---
        uint256 balancePostReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePostReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePostFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePostFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePostEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePostEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePostPaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePostPaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePostEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePostEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePostEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePostBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePostBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        // Assert balances
        _assertBalanceDiff(balancePreReceiverTokenIn, balancePostReceiverTokenIn, 0, "Receiver TokenIn (ETH)");
        _assertBalanceDiff(
            balancePreReceiverTokenOut,
            balancePostReceiverTokenOut,
            int256(shortcut.amountsIn[0] - shortcut.fee),
            "Receiver TokenOut (WETH)"
        );

        _assertBalanceDiff(
            balancePreFeeReceiverTokenIn,
            balancePostFeeReceiverTokenIn,
            int256(shortcut.fee),
            "FeeReceiver TokenIn (ETH)"
        );
        _assertBalanceDiff(
            balancePreFeeReceiverTokenOut, balancePostFeeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenIn,
            balancePostEnsoReceiverTokenIn,
            -int256(shortcut.amountsIn[0]),
            "EnsoReceiver TokenIn (ETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenOut, balancePostEnsoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(balancePrePaymasterTokenIn, balancePostPaymasterTokenIn, 0, "Paymaster TokenIn (ETH)");
        _assertBalanceDiff(balancePrePaymasterTokenOut, balancePostPaymasterTokenOut, 0, "Paymaster TokenOut (WETH)");

        _assertBalanceDiff(
            balancePreEntryPointPaymaster,
            balancePostEntryPointPaymaster,
            -2_007_965_471_000_526,
            "EntryPoint Paymaster balance (ETH)"
        );
        _assertBalanceDiff(
            balancePreEntryPointTokenIn,
            balancePostEntryPointTokenIn,
            -2_007_965_471_000_526,
            "EntryPoint TokenIn (ETH)"
        );
        _assertBalanceDiff(balancePreEntryPointTokenOut, balancePostEntryPointTokenOut, 0, "EntryPoint TokenOut (WETH)");

        _assertBalanceDiff(balancePreBundler1TokenIn, balancePostBundler1TokenIn, 0, "Bundler1 TokenIn (ETH)");
        _assertBalanceDiff(balancePreBundler1TokenOut, balancePostBundler1TokenOut, 0, "Bundler1 TokenOut (WETH)");
    }

    /**
     * @dev Should unsuccessfully execute the shortcut as expected:
     * - Caller is an EOA.
     * - EnsoReceiver sends 0.5 ETH back to receiver.
     * - Fee receiver doesn't earn fees.
     * - EntryPoint subtracts the execution cost from SignaturePaymaster balances.
     * - Bundler execution costs are refunded.
     */
    function test_unsuccessful_shortcut() public {
        // *** Arrange ***
        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1();

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(EOA_1));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(EOA_1);
        // NOTE: revert reason, `account.balance < shortcut.amountsIn[0]`
        uint256 accountTokenInBalance = shortcut.amountsIn[0] - 0.5 ether;
        (bool success,) = account.call{ value: accountTokenInBalance }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(EOA_1);

        // UserOp.nonce - Get nonce for the account
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // UserOp.callData - Encode the call to `EnsoReceiver.safeExecute`
        bytes memory callData = abi.encodeCall(
            EnsoReceiver.safeExecute, (IERC20(shortcut.tokensIn[0]), accountTokenInBalance, shortcut.txData)
        );
        userOp.callData = callData;

        // UserOp.accountGasLimits
        uint256 verificationGasLimit = 200_000;
        userOp.accountGasLimits = _accountGasLimits(shortcut.txGas, verificationGasLimit);

        // UserOp.gasFees
        userOp.gasFees = _gasFees();

        // UserOp.preVerificationGas
        userOp.preVerificationGas = 100_000;

        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp + 5 seconds);
        uint48 validAfter = uint48(block.timestamp - 5 seconds);
        uint128 paymasterVerificationGas = 100_000;
        uint128 paymasterPostOp = 100_000;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter);
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with ENSO_BACKEND's private key
        bytes32 pmdHash = s_paymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(ENSO_BACKEND_PK), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;

        // UserOp.signature - Sign the userOpHash with EOA_1's private key
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(EOA_1_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // --- Get balances before execution ---
        uint256 balancePreReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePreReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePreFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePreFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePreEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePreEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePrePaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePrePaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePreEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePreEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePreEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePreBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePreBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        bytes memory expectedErrorResponse =
            hex"ef3dcb2f0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000007556e6b6e6f776e00000000000000000000000000000000000000000000000000";

        // *** Act & Assert ***
        vm.expectEmit(address(account));
        emit EnsoReceiver.ShortcutExecutionFailed(expectedErrorResponse);
        vm.prank(BUNDLER_1);
        s_entryPoint.handleOps(userOps, BUNDLER_1);

        // *** Assert ***
        // --- Get balances after execution ---
        uint256 balancePostReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.receiver);
        uint256 balancePostReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.receiver);

        uint256 balancePostFeeReceiverTokenIn = _balance(shortcut.tokensIn[0], shortcut.feeReceiver);
        uint256 balancePostFeeReceiverTokenOut = _balance(shortcut.tokensOut[0], shortcut.feeReceiver);

        uint256 balancePostEnsoReceiverTokenIn = _balance(shortcut.tokensIn[0], address(account));
        uint256 balancePostEnsoReceiverTokenOut = _balance(shortcut.tokensOut[0], address(account));

        uint256 balancePostPaymasterTokenIn = _balance(shortcut.tokensIn[0], address(s_paymaster));
        uint256 balancePostPaymasterTokenOut = _balance(shortcut.tokensOut[0], address(s_paymaster));

        uint256 balancePostEntryPointPaymaster = s_entryPoint.balanceOf(address(s_paymaster));

        uint256 balancePostEntryPointTokenIn = _balance(shortcut.tokensIn[0], ENTRY_POINT_0_8);
        uint256 balancePostEntryPointTokenOut = _balance(shortcut.tokensOut[0], ENTRY_POINT_0_8);

        uint256 balancePostBundler1TokenIn = _balance(shortcut.tokensIn[0], BUNDLER_1);
        uint256 balancePostBundler1TokenOut = _balance(shortcut.tokensOut[0], BUNDLER_1);

        // Assert balances
        _assertBalanceDiff(
            balancePreReceiverTokenIn,
            balancePostReceiverTokenIn,
            int256(accountTokenInBalance),
            "Receiver TokenIn (ETH)"
        );
        _assertBalanceDiff(balancePreReceiverTokenOut, balancePostReceiverTokenOut, 0, "Receiver TokenOut (WETH)");

        _assertBalanceDiff(balancePreFeeReceiverTokenIn, balancePostFeeReceiverTokenIn, 0, "FeeReceiver TokenIn (ETH)");
        _assertBalanceDiff(
            balancePreFeeReceiverTokenOut, balancePostFeeReceiverTokenOut, 0, "FeeReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenIn,
            balancePostEnsoReceiverTokenIn,
            -int256(accountTokenInBalance),
            "EnsoReceiver TokenIn (ETH)"
        );

        _assertBalanceDiff(
            balancePreEnsoReceiverTokenOut, balancePostEnsoReceiverTokenOut, 0, "EnsoReceiver TokenOut (WETH)"
        );

        _assertBalanceDiff(balancePrePaymasterTokenIn, balancePostPaymasterTokenIn, 0, "Paymaster TokenIn (ETH)");
        _assertBalanceDiff(balancePrePaymasterTokenOut, balancePostPaymasterTokenOut, 0, "Paymaster TokenOut (WETH)");

        _assertBalanceDiff(
            balancePreEntryPointPaymaster,
            balancePostEntryPointPaymaster,
            -1_768_746_612_895_101,
            "EntryPoint Paymaster balance (ETH)"
        );
        _assertBalanceDiff(
            balancePreEntryPointTokenIn,
            balancePostEntryPointTokenIn,
            -1_768_746_612_895_101,
            "EntryPoint TokenIn (ETH)"
        );
        _assertBalanceDiff(balancePreEntryPointTokenOut, balancePostEntryPointTokenOut, 0, "EntryPoint TokenOut (WETH)");

        _assertBalanceDiff(balancePreBundler1TokenIn, balancePostBundler1TokenIn, 0, "Bundler1 TokenIn (ETH)");
        _assertBalanceDiff(balancePreBundler1TokenOut, balancePostBundler1TokenOut, 0, "Bundler1 TokenOut (WETH)");
    }

    /**
     * @dev Should revert because the shortcut’s Paymaster signature is not valid yet, `validAfter` in
     * `paymasterAndData` is in the future.
     * - Caller is an EOA.
     */
    function test_unsuccessful_shortcut_invalid_paymentdata_validafter() public {
        // *** Arrange ***
        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1();

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(EOA_1));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(EOA_1);
        (bool success,) = account.call{ value: shortcut.amountsIn[0] }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(EOA_1);

        // UserOp.nonce - Get nonce for the account
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // UserOp.callData - Encode the call to `EnsoReceiver.safeExecute`
        bytes memory callData = abi.encodeCall(
            EnsoReceiver.safeExecute, (IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData)
        );
        userOp.callData = callData;

        // UserOp.accountGasLimits
        uint256 verificationGasLimit = 200_000;
        userOp.accountGasLimits = _accountGasLimits(shortcut.txGas, verificationGasLimit);

        // UserOp.gasFees
        userOp.gasFees = _gasFees();

        // UserOp.preVerificationGas
        userOp.preVerificationGas = 100_000;

        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp + 5 seconds);
        uint48 validAfter = uint48(block.timestamp); // NOTE: revert cause
        uint128 paymasterVerificationGas = 100_000;
        uint128 paymasterPostOp = 100_000;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter);
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with ENSO_BACKEND's private key
        bytes32 pmdHash = s_paymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(ENSO_BACKEND_PK), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;

        // UserOp.signature - Sign the userOpHash with EOA_1's private key
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(EOA_1_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        uint256 userOpIndex = 0;
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[userOpIndex] = userOp;

        // *** Act & Assert ***
        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector, userOpIndex, "AA32 paymaster expired or not due")
        );
        vm.prank(BUNDLER_1);
        s_entryPoint.handleOps(userOps, BUNDLER_1);
    }

    /**
     * @dev Should revert because the shortcut’s Paymaster signature has expired, `validUntil` in
     * `paymasterAndData` is in the past.
     * - Caller is an EOA.
     */
    function test_unsuccessful_shortcut_invalid_paymentdata_validuntil() public {
        // *** Arrange ***
        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1();

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(EOA_1));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(EOA_1);
        (bool success,) = account.call{ value: shortcut.amountsIn[0] }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(EOA_1);

        // UserOp.nonce - Get nonce for the account
        uint192 laneId = 0;
        uint256 nonce = s_entryPoint.getNonce(account, laneId);
        userOp.nonce = nonce;

        // UserOp.callData - Encode the call to `EnsoReceiver.safeExecute`
        bytes memory callData = abi.encodeCall(
            EnsoReceiver.safeExecute, (IERC20(shortcut.tokensIn[0]), shortcut.amountsIn[0], shortcut.txData)
        );
        userOp.callData = callData;

        // UserOp.accountGasLimits
        uint256 verificationGasLimit = 200_000;
        userOp.accountGasLimits = _accountGasLimits(shortcut.txGas, verificationGasLimit);

        // UserOp.gasFees
        userOp.gasFees = _gasFees();

        // UserOp.preVerificationGas
        userOp.preVerificationGas = 100_000;

        // UserOp.paymasterAndData - Encode the paymaster and data
        uint48 validUntil = uint48(block.timestamp - 1 seconds); // NOTE: revert cause
        uint48 validAfter = uint48(block.timestamp - 5 seconds);
        uint128 paymasterVerificationGas = 100_000;
        uint128 paymasterPostOp = 100_000;
        // NOTE: signature will be added later
        bytes memory paymasterAndDataWoSignature =
            abi.encodePacked(address(s_paymaster), paymasterVerificationGas, paymasterPostOp, validUntil, validAfter);
        userOp.paymasterAndData = paymasterAndDataWoSignature;

        // NOTE: Sign first the `userOp.paymasterAndData` with ENSO_BACKEND's private key
        bytes32 pmdHash = s_paymaster.getHash(userOp, validUntil, validAfter);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(pmdHash);
        (uint8 pmdV, bytes32 pmdR, bytes32 pmdS) = vm.sign(uint256(ENSO_BACKEND_PK), ethSignedMessageHash);
        bytes memory pmdSignature = abi.encodePacked(pmdR, pmdS, pmdV);

        // NOTE: add `pmdSignature` to `userOp.paymasterAndData` (aka `paymasterAndDataWoSignature`)
        bytes memory paymasterAndData = abi.encodePacked(paymasterAndDataWoSignature, pmdSignature);
        userOp.paymasterAndData = paymasterAndData;

        // UserOp.signature - Sign the userOpHash with EOA_1's private key
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(EOA_1_PK), userOpHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        userOp.signature = signature;

        uint256 userOpIndex = 0;
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[userOpIndex] = userOp;

        // *** Act & Assert ***
        vm.expectRevert(
            abi.encodeWithSelector(IEntryPoint.FailedOp.selector, userOpIndex, "AA32 paymaster expired or not due")
        );
        vm.prank(BUNDLER_1);
        s_entryPoint.handleOps(userOps, BUNDLER_1);
    }

    function _assertBalanceDiff(
        uint256 balancePre,
        uint256 balancePost,
        int256 expectedDiff,
        string memory label
    )
        internal
        pure
    {
        int256 actualDiff = int256(balancePost) - int256(balancePre);
        assertEq(actualDiff, expectedDiff, string(abi.encodePacked("Balance diff mismatch: ", label)));
    }

    function _balance(address token, address account) internal view returns (uint256 balance) {
        balance = token == NATIVE_ASSET ? account.balance : IERC20(token).balanceOf(account);
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

    function _accountGasLimits(
        uint256 shortcutTxGas,
        uint256 verificationGasLimit // verifcation gas limit includes deployment costs
    )
        internal
        pure
        returns (bytes32 accountGasLimits)
    {
        accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(shortcutTxGas));
    }
}

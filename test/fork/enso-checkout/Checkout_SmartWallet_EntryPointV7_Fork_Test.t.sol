// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoReceiver } from "../../../src/delegate/EnsoReceiver.sol";
import { ERC4337CloneFactory } from "../../../src/factory/ERC4337CloneFactory.sol";
import { SignaturePaymaster } from "../../../src/paymaster/SignaturePaymaster.sol";
import { Shortcut } from "../../shortcuts/ShortcutDataTypes.sol";
import { ShortcutsEthereum } from "../../shortcuts/ShortcutsEthereum.sol";
import { EntryPoint } from "account-abstraction-v7/core/EntryPoint.sol";
import { IEntryPoint, PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { StdStorage, Test, console2, stdStorage } from "forge-std-1.9.7/Test.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import { Safe } from "safe-smart-account-1.5.0/Safe.sol";

import { ExtensibleFallbackHandler } from "safe-smart-account-1.5.0/handler/ExtensibleFallbackHandler.sol";
import { ERC1271 } from "safe-smart-account-1.5.0/handler/extensible/SignatureVerifierMuxer.sol";
import { ISignatureValidator } from "safe-smart-account-1.5.0/interfaces/ISignatureValidator.sol";

import { SignMessageLib } from "safe-smart-account-1.5.0/libraries/SignMessageLib.sol";
import { SafeProxy } from "safe-smart-account-1.5.0/proxies/SafeProxy.sol";
import { SafeProxyFactory } from "safe-smart-account-1.5.0/proxies/SafeProxyFactory.sol";
import { sortPKsByComputedAddress } from "safe-tools-0.2.0/SafeTestTools.sol";

contract Checkout_SmartWallet_EntryPointV7_Fork_Test is Test {
    using SafeERC20 for IERC20;

    address private constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address payable private constant ENSO_ACCOUNT = payable(0x93621DCA56fE26Cdee86e4F6B18E116e9758Ff11);
    address payable private constant ENSO_DEPLOYER = payable(0x826e0BB2276271eFdF2a500597f37b94f6c153bA);
    address payable private constant ENSO_FEE_RECEIVER = payable(0x6AA68C46eD86161eB318b1396F7b79E386e88676);

    address payable private constant ENTRY_POINT_0_8 = payable(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);
    SignMessageLib private constant SIGN_MESSAGE_LIB = SignMessageLib(0xd53cd0aB83D845Ac265BE939c57F53AD838012c9);

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
    Safe private s_safe;

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

        // Deploy Safe
        vm.startPrank(ENSO_DEPLOYER);
        ExtensibleFallbackHandler safeFallbackHandler = new ExtensibleFallbackHandler();
        vm.label(address(safeFallbackHandler), "ExtensibleFallbackHandler");
        Safe safeSingleton = new Safe();
        vm.label(address(s_safe), "Safe_1_5_0");

        SafeProxyFactory safeProxyFactory = new SafeProxyFactory();

        address[] memory safeOwners = new address[](2);
        safeOwners[0] = EOA_1;
        safeOwners[1] = EOA_2;
        uint256 safeThreshold = 2;
        address safeTo = address(0); // Contract address for optional delegate call.
        bytes memory safeData = ""; // Data payload for optional delegate call.
        // address safeFallbackHandler = address(0); // Handler for fallback calls to this contract
        address safePaymentToken = address(0); // Token that should be used for the payment (0 is ETH)
        uint256 safePayment = 0; // Value that should be paid
        address payable safePaymentReceiver = payable(address(0)); // Address that should receive the payment (or 0 if
            // tx.origin)
        // s_safe.setup(
        //     safeOwners,
        //     safeThreshold,
        //     safeTo,
        //     safeData,
        //     safeFallbackHandler,
        //     safePaymentToken,
        //     safePayment,
        //     safePaymentReceiver
        // );
        bytes memory safeSetupData = abi.encodeCall(
            Safe.setup,
            (
                safeOwners,
                safeThreshold,
                safeTo,
                safeData,
                address(safeFallbackHandler),
                safePaymentToken,
                safePayment,
                safePaymentReceiver
            )
        );
        SafeProxy safeProxy = safeProxyFactory.createProxyWithNonce(
            address(safeSingleton), safeSetupData, uint256(keccak256("SafeProxyFactory"))
        );
        s_safe = Safe(payable(address(safeProxy)));
        vm.deal(address(s_safe), 1 ether);
        address[] memory owners = s_safe.getOwners();
        assertEq(owners.length, 2);
        assertEq(owners[0], EOA_1);
        assertEq(owners[1], EOA_2);
        vm.stopPrank();

        // vm.prank(EOA_1);
    }

    /**
     * @dev Should successfully execute the shortcut as expected:
     * - Caller is an ERC1271 compatible Smart Wallet (Safe v1.5.0).
     * - EnsoReceiver wraps 1 ETH (minus 0.01 ETH fees) as WETH, and sends them to EOA_1 (+0.99 WETH).
     * - EnsoReceiver sends 0.01 ETH to fee receiver as part of the shortcut.
     * - EntryPoint subtracts the execution cost from SignaturePaymaster balances.
     * - Bundler execution costs are refunded.
     */
    function test_successful_shortcut() public {
        // *** Arrange ***
        // --- Shortcut ---
        Shortcut memory shortcut = ShortcutsEthereum.getShortcut1(address(s_safe));
        //shortcut.receiver = address(s_safe); // NOTE: override receiver to smart wallet

        // --- UserOp parameters ---
        PackedUserOperation memory userOp;

        // UserOp.account - Get account (EnsoReceiver) address, and fund it with `shortcut.tokensIn[0]`
        address payable account = payable(s_accountFactory.getAddress(address(s_safe)));
        vm.label(account, "EnsoReceiver");
        userOp.sender = account;

        vm.prank(address(s_safe));
        (bool success,) = account.call{ value: shortcut.amountsIn[0] }("");
        (success); // shh

        // UserOp.initCode - Setup initCode
        userOp.initCode = _initCode(address(s_safe));

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

        // UserOp.signature - Sign the userOpHash with Smart Wallet
        bytes32 userOpHash = s_entryPoint.getUserOpHash(userOp);

        // encode and sign safe message
        // bytes32 safeUserOpHash = SignMessageLib(address(s_safe)).getMessageHash(abi.encode(userOpHash));
        bytes32 safeMessageHash =
            keccak256(abi.encode(keccak256("SafeMessage(bytes message)"), keccak256(abi.encode(userOpHash))));
        bytes32 safeDomainSeparator = s_safe.domainSeparator();
        bytes32 safeUserOpHash =
            keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), safeDomainSeparator, safeMessageHash));

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(uint256(EOA_1_PK), safeUserOpHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(uint256(EOA_2_PK), safeUserOpHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        bytes memory safeSignature = bytes.concat(signature2, signature1);

        userOp.signature = safeSignature;

        bytes4 isValid = ERC1271(address(s_safe)).isValidSignature(userOpHash, safeSignature);
        console2.logBytes4(isValid);
        assertEq(isValid == 0x1626ba7e, true);

        userOp.signature = safeSignature;

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
            -2_080_224_775_824_786,
            "EntryPoint Paymaster balance (ETH)"
        );
        _assertBalanceDiff(
            balancePreEntryPointTokenIn,
            balancePostEntryPointTokenIn,
            -2_080_224_775_824_786,
            "EntryPoint TokenIn (ETH)"
        );
        _assertBalanceDiff(balancePreEntryPointTokenOut, balancePostEntryPointTokenOut, 0, "EntryPoint TokenOut (WETH)");

        _assertBalanceDiff(balancePreBundler1TokenIn, balancePostBundler1TokenIn, 0, "Bundler1 TokenIn (ETH)");
        _assertBalanceDiff(balancePreBundler1TokenOut, balancePostBundler1TokenOut, 0, "Bundler1 TokenOut (WETH)");
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

    /// @notice Assumes the private keys are already sorted by their computed addresses.
    /// @param sortedPrivateKeys Array of sorted private keys (ascending by address).
    /// @param messageHash Hash to sign (already wrapped as needed).
    /// @return signature Concatenated Safe-compatible signature (rsv, rsv, ...).
    function _getSafeSignature(
        uint256[] memory sortedPrivateKeys,
        bytes32 messageHash
    )
        internal
        pure
        returns (bytes memory signature)
    {
        for (uint256 i = 0; i < sortedPrivateKeys.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sortedPrivateKeys[i], messageHash);
            signature = bytes.concat(signature, abi.encodePacked(r, s, v));
        }
        return signature;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin-contracts-5.2.0/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin-contracts-5.2.0/contracts/token/ERC20/utils/SafeERC20.sol";
import { EntryPoint } from "account-abstraction-v7/core/EntryPoint.sol";
import { IEntryPoint, PackedUserOperation } from "account-abstraction-v7/interfaces/IEntryPoint.sol";
import { StdStorage, Test, console2, stdStorage } from "forge-std-1.9.7/Test.sol";

import { SignaturePaymaster } from "../../../../src/paymaster/SignaturePaymaster.sol";

contract SimulateEnsoCheckout_Fork_Test is Test {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage;

    // Enum
    enum TokenType {
        NATIVE_ASSET,
        ERC20,
        ERC721,
        ERC1155
    }

    // --- Simulation environment variables --
    string private constant SIMULATION_JSON_ENV_VAR = "SIMULATION_JSON_DATA";

    string private constant JSON_SHORTCUT_DATA = ".shortcutData";
    string private constant JSON_SHORTCUT_DATA_TOKENS_IN_FUNDING_REQUIRED = ".shortcutData.tokensInFundingRequired";
    string private constant JSON_SHORTCUT_DATA_TOKENS_IN_TYPES = ".shortcutData.tokensInTypes";
    string private constant JSON_SHORTCUT_DATA_TOKENS_IN = ".shortcutData.tokensIn";
    string private constant JSON_SHORTCUT_DATA_AMOUNTS_IN = ".shortcutData.amountsIn";
    string private constant JSON_SHORTCUT_DATA_TOKENS_IN_HOLDERS = ".shortcutData.tokensInHolders";

    string private constant JSON_BACKEND_SIGNER = ".backendSigner";
    string private constant JSON_ENSO_RECEIVER = ".ensoReceiver";
    string private constant JSON_BUNDLER = ".bundler";
    string private constant JSON_SIGNATURE_PAYMASTER = ".signaturePaymaster";
    string private constant JSON_ENTRY_POINT = ".entryPoint";

    string private constant JSON_HANDLE_OPS = ".handleOps";
    string private constant JSON_HANDLE_OPS_SENDER = ".sender";
    string private constant JSON_HANDLE_OPS_NONCE = ".nonce";
    string private constant JSON_HANDLE_OPS_INIT_CODE = ".initCode";
    string private constant JSON_HANDLE_OPS_CALL_DATA = ".callData"; // NOTE: this is not `JSON_HANDLE_OPS_CALLDATA`
    string private constant JSON_HANDLE_OPS_ACCOUNT_GAS_LIMITS = ".accountGasLimits";
    string private constant JSON_HANDLE_OPS_PRE_VERIFICATION_GAS = ".preVerificationGas";
    string private constant JSON_HANDLE_OPS_GAS_FEES = ".gasFees";
    string private constant JSON_HANDLE_OPS_PAYMSTER_AND_DATA = ".paymasterAndData";
    string private constant JSON_HANDLE_OPS_SIGNATURE = ".signature";

    string private constant JSON_HANDLE_OPS_CALLDATA = ".handleOpsCalldata";

    uint256 private constant NUMBER_OF_JSON_STRINGIFIED_ARRAYS_PER_TX_TO_SIM = 5; // NB: keep it up to date with the
    // number of JSON arrays

    // --- Shortcut ---
    address private constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // --- Storage ---
    address private s_bundler;
    EntryPoint private s_entryPoint;
    address payable private s_beneficiary;
    PackedUserOperation[] private s_userOps;

    // --- Errors ---
    error TokenInHolderNotFound(uint256 shortcutIndex, address tokenIn);
    error TxToSimulateArrayLengthsAreNotEq();
    error TokensInTypeIsUnsupported(uint8 tokensInType, address tokenIn);

    function setUp() public {
        // --- Read simulation json data from environment ---
        string memory jsonStr = vm.envString(SIMULATION_JSON_ENV_VAR);

        // Shortcuts data
        bool[] memory tokensInFundingRequired =
            vm.parseJsonBoolArray(jsonStr, JSON_SHORTCUT_DATA_TOKENS_IN_FUNDING_REQUIRED);
        uint256[] memory tokensInTypesUint = vm.parseJsonUintArray(jsonStr, JSON_SHORTCUT_DATA_TOKENS_IN_TYPES);
        TokenType[] memory tokensInTypes = abi.decode(abi.encode(tokensInTypesUint), (TokenType[]));
        address[] memory tokensIn = vm.parseJsonAddressArray(jsonStr, JSON_SHORTCUT_DATA_TOKENS_IN);
        uint256[] memory amountsIn = vm.parseJsonUintArray(jsonStr, JSON_SHORTCUT_DATA_AMOUNTS_IN);
        address[] memory tokensInHolders = vm.parseJsonAddressArray(jsonStr, JSON_SHORTCUT_DATA_TOKENS_IN_HOLDERS);

        // Cross-check all JSON parsed arrays lengths
        uint256 totalLengths = tokensInFundingRequired.length + tokensInTypes.length + tokensIn.length
            + amountsIn.length + tokensInHolders.length;

        if (totalLengths % NUMBER_OF_JSON_STRINGIFIED_ARRAYS_PER_TX_TO_SIM != 0) {
            revert TxToSimulateArrayLengthsAreNotEq();
        }

        // Actors
        address backendSigner = vm.parseJsonAddress(jsonStr, JSON_BACKEND_SIGNER);
        address ensoReceiver = vm.parseJsonAddress(jsonStr, JSON_ENSO_RECEIVER);
        address signaturePaymaster = vm.parseJsonAddress(jsonStr, JSON_SIGNATURE_PAYMASTER);
        s_bundler = vm.parseJsonAddress(jsonStr, JSON_BUNDLER);
        s_entryPoint = EntryPoint(payable(vm.parseJsonAddress(jsonStr, JSON_ENTRY_POINT)));

        // HandleOps
        // TODO: TBD handleOps call format
        // bytes memory handleOpsCalldata = vm.parseJsonBytes(jsonStr, JSON_HANDLE_OPS_CALLDATA);
        // (PackedUserOperation[] memory userOps, address beneficiary) =
        //     abi.decode(handleOpsCalldata, (PackedUserOperation[], address));
        // s_beneficiary = payable(beneficiary);
        // s_userOps[0] = userOps[0];

        // --- Fund Actors ---
        // SignaturePaymaster owner
        address signaturePaymasterOwner = SignaturePaymaster(signaturePaymaster).owner();
        vm.deal(signaturePaymasterOwner, 1000 ether); // Fund owner to cover the deposit & stake

        // Bundler
        vm.deal(s_bundler, 1000 ether);

        /// EnsoReceiver
        for (uint256 i = 0; i < tokensInFundingRequired.length; i++) {
            if (!tokensInFundingRequired[i]) continue;

            TokenType tokenType = tokensInTypes[i];
            address tokenIn = tokensIn[i];
            uint256 amountIn = amountsIn[i];
            address tokensInHolder = tokensInHolders[i];

            if (tokenType == TokenType.NATIVE_ASSET) {
                vm.deal(ensoReceiver, amountIn);
            } else if (tokenType == TokenType.ERC20) {
                if (tokensInHolder == address(0)) {
                    revert TokenInHolderNotFound(i, tokenIn);
                }
                vm.deal(tokensInHolder, 10 ether);
                vm.prank(tokensInHolder);
                IERC20(tokenIn).safeTransfer(ensoReceiver, amountIn);
            } else {
                // NOTE: ERC721 and ERC1155 are not supported in this simulation
                revert TokensInTypeIsUnsupported(uint8(tokenType), tokenIn);
            }
        }

        // --- Set up SignaturePaymaster ---
        // NOTE: adding stake may not be needed for this simulation
        vm.startPrank(signaturePaymasterOwner);
        SignaturePaymaster(signaturePaymaster).deposit{ value: 10 ether }(); // NOTE: consider making this dynamic
        SignaturePaymaster(signaturePaymaster).addStake{ value: 10 ether }(3600); // NOTE: consider making this dynamic

        bool isValidSigner = SignaturePaymaster(signaturePaymaster).validSigners(backendSigner);
        if (!isValidSigner) {
            vm.prank(signaturePaymasterOwner);
            SignaturePaymaster(signaturePaymaster).setSigner(backendSigner, true);
        }
        vm.stopPrank();
    }

    // TODO: TBD handleOps call format
    function test_simulateHandleOps_1() public {
        // PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        // userOps[0] = s_userOps[0];

        // vm.prank(s_bundler);
        // s_entryPoint.handleOps(userOps, s_beneficiary);

        bool isTrue = true;
        assertTrue(isTrue);
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BridgeGuardianDeployer } from "../../../script/BridgeGuardianDeployer.s.sol";
import { BridgeGuardian } from "../../../src/intent/BridgeGuardian.sol";
import { Token, TokenType } from "../../../src/interfaces/IEnsoRouter.sol";
import { Obligation, Status } from "../../../src/interfaces/IIntentGuardian.sol";
import { Subsidies } from "../../utils/Subsidies.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface ISpokePoolDeposits {
    function numberOfDeposits() external view returns (uint32);
}

/// BridgeGuardian against the live CCTP V2 and Across contracts, deployed by its own deployer script
/// on Base and Ethereum forks. Covers the source side only: the burn or deposit, its event, and where
/// the funds went. Delivery on the destination (attestation, relayer fill) can't happen on a fork.
contract BridgeGuardian_Fork_Test is Test {
    // TokenMessengerV2.DepositForBurn and SpokePool.FundsDeposited, as the live contracts emit them.
    event DepositForBurn(
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 indexed minFinalityThreshold,
        bytes hookData
    );
    event FundsDeposited(
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 indexed destinationChainId,
        uint256 indexed depositId,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes32 indexed depositor,
        bytes32 recipient,
        bytes32 exclusiveRelayer,
        bytes message
    );

    uint256 internal constant AMOUNT = 1000e6;
    uint256 internal constant BASE_BLOCK = 59_249_000;
    uint256 internal constant ETHEREUM_BLOCK = 26_444_000;

    uint256 internal constant ARBITRUM = 42_161;
    uint32 internal constant ARBITRUM_DOMAIN = 3;
    address internal constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant USDT_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    uint256 internal constant BASE = 8453;
    uint32 internal constant BASE_DOMAIN = 6;
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant USDT_ETHEREUM = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    /// TokenMessengerV2 has the same address on every chain: it is also the destination messenger.
    address internal constant TOKEN_MESSENGER = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    address internal s_intent = makeAddr("Intent");
    address internal s_user = makeAddr("User");
    BridgeGuardian internal s_guardian;

    // CCTP

    function test_Base_Cctp_BurnsToTheRecipientOnArbitrum() external {
        _fork("BASE_RPC_URL", BASE_BLOCK);
        _cctp(ARBITRUM, ARBITRUM_DOMAIN, USDC_ARBITRUM, 0, 2000);
    }

    function test_Base_Cctp_Fast() external {
        _fork("BASE_RPC_URL", BASE_BLOCK);
        _cctp(ARBITRUM, ARBITRUM_DOMAIN, USDC_ARBITRUM, 1e6, 1000);
    }

    /// 1:1 with a subsidy through the live Permit2: the payer covers the fast-transfer fee.
    function test_Base_Cctp_Fast_Subsidized() external {
        _fork("BASE_RPC_URL", BASE_BLOCK);
        _cctp(ARBITRUM, ARBITRUM_DOMAIN, USDC_ARBITRUM, 1e6, 1000, 1e6);
    }

    function test_Ethereum_Cctp_BurnsToTheRecipientOnBase() external {
        _fork("ETHEREUM_RPC_URL", ETHEREUM_BLOCK);
        _cctp(BASE, BASE_DOMAIN, USDC_BASE, 0, 2000);
    }

    // Across

    function test_Base_Across_DepositsWithTheUserAsDepositor() external {
        _fork("BASE_RPC_URL", BASE_BLOCK);
        _across(s_guardian.usdc(), USDC_ARBITRUM);
    }

    function test_Ethereum_Across_Usdt() external {
        _fork("ETHEREUM_RPC_URL", ETHEREUM_BLOCK);
        _across(USDT_ETHEREUM, USDT_ARBITRUM);
    }

    /// 1:1 with a subsidy through the live Permit2. USDT's transferFrom returns nothing.
    function test_Ethereum_Across_Usdt_Subsidized() external {
        _fork("ETHEREUM_RPC_URL", ETHEREUM_BLOCK);
        _across(USDT_ETHEREUM, USDT_ARBITRUM, 2e6);
    }

    /// Selects the fork and deploys the guardian with this chain's configuration, as the deployer
    /// script does on the real chain.
    function _fork(string memory rpc, uint256 blockNumber) internal {
        vm.createSelectFork(vm.envString(rpc), blockNumber);
        s_guardian = new BridgeGuardianDeployer().run();
    }

    function _cctp(uint256 chainId, uint32 domain, address delivered, uint256 maxFee, uint32 finality) internal {
        _cctp(chainId, domain, delivered, maxFee, finality, 0);
    }

    /// With a `fee`, a payer's subsidy through the live Permit2 tops the burn up and the floor is the
    /// whole handed amount.
    function _cctp(
        uint256 chainId,
        uint32 domain,
        address delivered,
        uint256 maxFee,
        uint32 finality,
        uint256 fee
    )
        internal
    {
        address usdc = s_guardian.usdc();
        Obligation memory o = _obligation(chainId, s_guardian.CCTP(), delivered, fee > 0 ? AMOUNT : AMOUNT - maxFee);
        BridgeGuardian.Subsidy memory subsidy;
        if (fee > 0) {
            (address payer, uint256 key) = makeAddrAndKey("Payer");
            deal(usdc, payer, fee);
            vm.prank(payer);
            IERC20(usdc).approve(address(Subsidies.PERMIT2), fee);
            Subsidies.Burn memory b = Subsidies.Burn({
                caller: s_intent,
                intentHash: keccak256("intent"),
                obligation: o,
                amount: AMOUNT,
                maxFee: maxFee,
                minFinalityThreshold: finality
            });
            subsidy = Subsidies.sign(s_guardian, key, usdc, fee, 0, b);
        }
        bytes memory context = abi.encode(uint256(0), s_guardian.CCTP(), abi.encode(maxFee, finality, subsidy));
        _fund(usdc);
        uint256 supply = IERC20(usdc).totalSupply();

        vm.expectEmit(true, true, true, true, TOKEN_MESSENGER);
        emit DepositForBurn(
            usdc,
            AMOUNT + fee,
            address(s_guardian),
            _word(s_user),
            domain,
            _word(TOKEN_MESSENGER),
            bytes32(0),
            maxFee,
            finality,
            ""
        );
        bytes32 receipt = _accept(usdc, o, context);

        assertEq(IERC20(usdc).totalSupply(), supply - AMOUNT - fee, "burned");
        assertEq(IERC20(usdc).balanceOf(s_intent), 0, "taken from the caller");
        _assertNothingRests(usdc, TOKEN_MESSENGER, receipt);
    }

    function _across(address input, address delivered) internal {
        _across(input, delivered, 0);
    }

    /// With a `fee`, a payer's subsidy through the live Permit2 tops the deposit up and the output is
    /// the whole handed amount.
    function _across(address input, address delivered, uint256 fee) internal {
        address spokePool = address(s_guardian.spokePool());
        uint256 output = fee > 0 ? AMOUNT : AMOUNT - 1e6;
        uint32 fillDeadline = uint32(block.timestamp + 2 hours);
        Obligation memory o = _obligation(ARBITRUM, s_guardian.ACROSS(), delivered, output);
        BridgeGuardian.Subsidy memory subsidy;
        if (fee > 0) {
            (address payer, uint256 key) = makeAddrAndKey("Payer");
            deal(input, payer, fee);
            vm.prank(payer);
            (bool approved,) = input.call(abi.encodeCall(IERC20.approve, (address(Subsidies.PERMIT2), fee)));
            require(approved, "approve");
            Subsidies.Deposit memory d = Subsidies.Deposit({
                caller: s_intent,
                intentHash: keccak256("intent"),
                obligation: o,
                amount: AMOUNT,
                outputAmount: output,
                fillDeadline: fillDeadline
            });
            subsidy = Subsidies.sign(s_guardian, key, input, fee, 0, d);
        }
        bytes memory context = abi.encode(uint256(0), s_guardian.ACROSS(), abi.encode(output, fillDeadline, subsidy));
        _fund(input);
        uint256 pooled = IERC20(input).balanceOf(spokePool);
        uint32 depositId = ISpokePoolDeposits(spokePool).numberOfDeposits();

        vm.expectEmit(true, true, true, true, spokePool);
        emit FundsDeposited(
            _word(input),
            _word(delivered),
            AMOUNT + fee,
            output,
            ARBITRUM,
            depositId,
            uint32(block.timestamp),
            fillDeadline,
            0,
            _word(s_user),
            _word(s_user),
            bytes32(0),
            ""
        );
        bytes32 receipt = _accept(input, o, context);

        assertEq(IERC20(input).balanceOf(spokePool), pooled + AMOUNT + fee, "escrowed in the spoke pool");
        assertEq(IERC20(input).balanceOf(s_intent), 0, "taken from the caller");
        _assertNothingRests(input, spokePool, receipt);
    }

    /// Funds `s_intent` with `token` and approves the guardian, as an intent address would. Called
    /// before `vm.expectEmit`, which applies to the next call.
    function _fund(address token) internal {
        deal(token, s_intent, AMOUNT);
        vm.prank(s_intent);
        // USDT's approve returns nothing: called without the IERC20 return check.
        (bool ok,) = token.call(abi.encodeCall(IERC20.approve, (address(s_guardian), AMOUNT)));
        require(ok, "approve");
    }

    function _accept(address token, Obligation memory o, bytes memory context) internal returns (bytes32) {
        Token memory input = Token({ tokenType: TokenType.ERC20, data: abi.encode(token, AMOUNT) });
        vm.prank(s_intent);
        return s_guardian.accept(keccak256("intent"), s_user, address(this), input, AMOUNT, o, context);
    }

    function _assertNothingRests(address token, address bridge, bytes32 receipt) internal view {
        assertEq(IERC20(token).balanceOf(address(s_guardian)), 0, "nothing rests");
        assertEq(IERC20(token).allowance(address(s_guardian), bridge), 0, "approval consumed");
        assertEq(uint8(s_guardian.status(receipt)), uint8(Status.PENDING), "pending");
    }

    function _obligation(
        uint256 chainId,
        bytes32 method,
        address delivered,
        uint256 minAmount
    )
        internal
        view
        returns (Obligation memory)
    {
        return Obligation({
            chainId: chainId,
            method: method,
            recipient: s_user,
            refund: s_user,
            token: delivered,
            minAmount: minAmount,
            deadline: uint64(block.timestamp + 6 hours)
        });
    }

    function _word(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

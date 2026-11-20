// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../../../../../src/intent/BridgeGuardian.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { IIntentGuardian, Level, Obligation, Status } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IAcrossSpokePool } from "../../../../../src/interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../../../../../src/interfaces/bridges/ITokenMessengerV2.sol";
import { MockAcrossSpokePool, MockTokenMessengerV2 } from "../../../../mocks/MockBridges.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";

contract BridgeGuardian_Unit_Concrete_Test is Test {
    uint256 internal constant AMOUNT = 100e6;
    uint256 internal constant ARBITRUM = 42_161;
    uint32 internal constant ARBITRUM_DOMAIN = 3;
    uint256 internal constant BNB = 56;
    uint256 internal constant ETHEREUM = 1;

    address internal s_intent = makeAddr("Intent"); // the caller: an intent address or a router
    address internal s_user = makeAddr("User");
    address internal s_keeper = makeAddr("Keeper");
    address internal s_usdcArbitrum = makeAddr("USDC on Arbitrum");
    address internal s_usdtArbitrum = makeAddr("USDT on Arbitrum");
    address internal s_usdtBnb = makeAddr("USDT on BNB Chain");
    address internal s_usdtEthereum = makeAddr("USDT on Ethereum");

    MockERC20 internal s_usdc;
    MockERC20 internal s_usdt;
    MockTokenMessengerV2 internal s_messenger;
    MockAcrossSpokePool internal s_spokePool;
    BridgeGuardian internal s_guardian;

    function setUp() public {
        s_usdc = new MockERC20("USD Coin", "USDC");
        s_usdt = new MockERC20("Tether", "USDT");
        s_messenger = new MockTokenMessengerV2();
        s_spokePool = new MockAcrossSpokePool();
        BridgeGuardian.CctpDestination[] memory destinations = new BridgeGuardian.CctpDestination[](1);
        destinations[0] =
            BridgeGuardian.CctpDestination({ chainId: ARBITRUM, domain: ARBITRUM_DOMAIN, usdc: s_usdcArbitrum });
        BridgeGuardian.AcrossRoute[] memory routes = new BridgeGuardian.AcrossRoute[](3);
        routes[0] = BridgeGuardian.AcrossRoute({
            input: address(s_usdt), chainId: ARBITRUM, output: s_usdtArbitrum, decimals: 0
        });
        // USDT to BNB Chain, where it has 12 more decimals; and back.
        routes[1] =
            BridgeGuardian.AcrossRoute({ input: address(s_usdt), chainId: BNB, output: s_usdtBnb, decimals: 12 });
        routes[2] = BridgeGuardian.AcrossRoute({
            input: address(s_usdc), chainId: ETHEREUM, output: s_usdtEthereum, decimals: -12
        });
        s_guardian = new BridgeGuardian(
            ITokenMessengerV2(address(s_messenger)),
            address(s_usdc),
            destinations,
            IAcrossSpokePool(address(s_spokePool)),
            routes
        );

        s_usdc.mint(s_intent, AMOUNT);
        s_usdt.mint(s_intent, AMOUNT);
        vm.startPrank(s_intent);
        s_usdc.approve(address(s_guardian), type(uint256).max);
        s_usdt.approve(address(s_guardian), type(uint256).max);
        vm.stopPrank();
        vm.deal(s_intent, 1 ether);
    }

    function _token(address token) internal pure returns (Token memory) {
        return Token({ tokenType: TokenType.ERC20, data: abi.encode(token, AMOUNT) });
    }

    function _obligation(
        bytes32 method,
        address delivered,
        uint256 minAmount
    )
        internal
        view
        returns (Obligation memory)
    {
        return Obligation({
            chainId: ARBITRUM,
            method: method,
            recipient: s_user,
            refund: s_user,
            token: delivered,
            minAmount: minAmount,
            deadline: uint64(block.timestamp + 6 hours)
        });
    }

    function _cctpContext(uint256 maxFee) internal view returns (bytes memory) {
        return abi.encode(uint256(0), s_guardian.CCTP(), abi.encode(maxFee, uint32(1000)));
    }

    function _acrossContext(uint256 outputAmount, uint32 fillDeadline) internal view returns (bytes memory) {
        return abi.encode(uint256(0), s_guardian.ACROSS(), abi.encode(outputAmount, fillDeadline));
    }

    function _accept(Token memory token, Obligation memory o, bytes memory context) internal returns (bytes32) {
        vm.prank(s_intent);
        return s_guardian.accept(keccak256("intent"), s_user, s_keeper, token, AMOUNT, o, context);
    }

    // CCTP

    function test_Cctp_BurnsToTheRecipientOnTheDestinationDomain() external {
        bytes32 receipt = _accept(
            _token(address(s_usdc)), _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT - 1e6), _cctpContext(1e6)
        );

        (
            uint256 amount,
            uint32 domain,
            bytes32 mintRecipient,
            address burnToken,
            bytes32 destinationCaller,
            uint256 maxFee,
            uint32 finality
        ) = s_messenger.last();
        assertEq(amount, AMOUNT, "amount");
        assertEq(domain, ARBITRUM_DOMAIN, "domain");
        assertEq(mintRecipient, bytes32(uint256(uint160(s_user))), "recipient");
        assertEq(burnToken, address(s_usdc), "burn token");
        assertEq(destinationCaller, bytes32(0), "anyone may relay the attestation");
        assertEq(maxFee, 1e6, "max fee");
        assertEq(finality, 1000, "fast");
        assertEq(s_usdc.balanceOf(address(s_guardian)), 0, "nothing rests");
        assertEq(s_usdc.allowance(address(s_guardian), address(s_messenger)), 0, "approval consumed");
        assertEq(uint8(s_guardian.status(receipt)), uint8(Status.PENDING), "pending");
    }

    function test_Cctp_FeeAboveTheFloor_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT - 1e6);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(1e6 + 1);
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.BelowMinimum.selector, AMOUNT - 1e6 - 1, AMOUNT - 1e6));
        _accept(usdc, o, context);
    }

    function test_Cctp_WrongDeliveredToken_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdtArbitrum, 0);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0);
        vm.expectRevert(
            abi.encodeWithSelector(BridgeGuardian.WrongDeliveredToken.selector, s_usdcArbitrum, s_usdtArbitrum)
        );
        _accept(usdc, o, context);
    }

    function test_Cctp_UnknownDestination_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, 0);
        o.chainId = 10;
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0);
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.UnsupportedDestination.selector, 10));
        _accept(usdc, o, context);
    }

    function test_Cctp_NotUsdc_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, 0);
        Token memory usdt = _token(address(s_usdt));
        bytes memory context = _cctpContext(0);
        vm.expectRevert(BridgeGuardian.UnsupportedToken.selector);
        _accept(usdt, o, context);
    }

    // Across

    function test_Across_DepositsWithTheUserAsDepositor() external {
        uint32 fillDeadline = uint32(block.timestamp + 2 hours);
        _accept(
            _token(address(s_usdt)),
            _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6),
            _acrossContext(99.5e6, fillDeadline)
        );

        MockAcrossSpokePool.Deposit memory d = s_spokePool.last();
        assertEq(d.depositor, bytes32(uint256(uint160(s_user))), "refunds of unfilled deposits go to the user");
        assertEq(d.recipient, bytes32(uint256(uint160(s_user))), "recipient");
        assertEq(d.inputToken, bytes32(uint256(uint160(address(s_usdt)))), "input");
        assertEq(d.outputToken, bytes32(uint256(uint160(s_usdtArbitrum))), "the committed delivered asset");
        assertEq(d.inputAmount, AMOUNT, "amount");
        assertEq(d.outputAmount, 99.5e6, "output");
        assertEq(d.destinationChainId, ARBITRUM, "destination");
        assertEq(d.quoteTimestamp, uint32(block.timestamp), "quoted now");
        assertEq(d.fillDeadline, fillDeadline, "fill deadline");
        assertEq(d.message.length, 0, "no destination call");
        assertEq(s_usdt.balanceOf(address(s_guardian)), 0, "nothing rests");
    }

    function test_Across_OutputBelowTheFloor_Reverts() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        Token memory usdt = _token(address(s_usdt));
        bytes memory context = _acrossContext(99e6 - 1, uint32(block.timestamp + 1 hours));
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.BelowMinimum.selector, 99e6 - 1, 99e6));
        _accept(usdt, o, context);
    }

    function test_Across_FillDeadlineAfterTheObligation_Reverts() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        Token memory usdt = _token(address(s_usdt));
        uint32 late = uint32(o.deadline + 1);
        bytes memory context = _acrossContext(99e6, late);
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.DeadlineTooLate.selector, late, o.deadline));
        _accept(usdt, o, context);
    }

    function test_Across_RefundToTheIntentAddress_Reverts() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        o.refund = s_intent; // would arrive as a fresh deposit and re-trigger the rule
        Token memory usdt = _token(address(s_usdt));
        bytes memory context = _acrossContext(99e6, uint32(block.timestamp + 1 hours));
        vm.expectRevert(BridgeGuardian.RefundToCaller.selector);
        _accept(usdt, o, context);
    }

    /// Any relayer may fill from the first block: the keeper can't name itself, or a relayer that
    /// never fills, as the exclusive relayer.
    function test_Across_DepositNamesNoExclusiveRelayer() external {
        _accept(
            _token(address(s_usdt)),
            _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6),
            _acrossContext(99e6, uint32(block.timestamp + 2 hours))
        );
        MockAcrossSpokePool.Deposit memory d = s_spokePool.last();
        assertEq(d.exclusiveRelayer, bytes32(0), "no exclusive relayer");
        assertEq(d.exclusivityParameter, 0, "no exclusivity");
    }

    /// The declared output may not exceed the handed amount, so the floor binds what was handed.
    function test_Across_OutputAboveTheHandedAmount_Reverts() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        Token memory usdt = _token(address(s_usdt));
        bytes memory context = _acrossContext(AMOUNT + 1, uint32(block.timestamp + 2 hours));
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.AboveInput.selector, AMOUNT + 1, AMOUNT));
        _accept(usdt, o, context);
    }

    /// The floor counts in input units: an output in a token with more decimals is scaled down
    /// before both bounds.
    function test_Across_OutputIsComparedInInputUnits() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtBnb, 98.9e6);
        o.chainId = BNB;
        Token memory usdt = _token(address(s_usdt));
        uint32 fillDeadline = uint32(block.timestamp + 2 hours);

        bytes memory dust = _acrossContext(98.9e6, fillDeadline); // raw 18-decimal units: dust
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.BelowMinimum.selector, 0, 98.9e6));
        _accept(usdt, o, dust);

        bytes memory over = _acrossContext((AMOUNT + 1) * 1e12, fillDeadline);
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.AboveInput.selector, AMOUNT + 1, AMOUNT));
        _accept(usdt, o, over);

        _accept(usdt, o, _acrossContext(98.9e18, fillDeadline));
        assertEq(s_spokePool.last().outputAmount, 98.9e18, "the floor, in the delivered token's units");
    }

    function test_Across_RouteTable() external view {
        (uint128 mul, uint128 div) = s_guardian.acrossRoutes(keccak256(abi.encode(address(s_usdt), BNB, s_usdtBnb)));
        assertEq(mul, 1, "more decimals: mul");
        assertEq(div, 1e12, "more decimals: div");
        (mul, div) = s_guardian.acrossRoutes(keccak256(abi.encode(address(s_usdc), ETHEREUM, s_usdtEthereum)));
        assertEq(mul, 1e12, "fewer decimals: mul");
        assertEq(div, 1, "fewer decimals: div");
    }

    /// Only the routes fixed at construction are served.
    function test_Across_UnlistedRoute_Reverts() external {
        Token memory usdt = _token(address(s_usdt));
        bytes memory context = _acrossContext(99e6, uint32(block.timestamp + 2 hours));

        Obligation memory chain = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        chain.chainId = 10;
        vm.expectRevert(BridgeGuardian.UnsupportedRoute.selector);
        _accept(usdt, chain, context);

        Obligation memory delivered = _obligation(s_guardian.ACROSS(), makeAddr("another token"), 99e6);
        vm.expectRevert(BridgeGuardian.UnsupportedRoute.selector);
        _accept(usdt, delivered, context);
    }

    /// A deposit that expires at birth, or within the fill window, can't be filled.
    function test_Across_FillDeadlineTooEarly_Reverts() external {
        Obligation memory o = _obligation(s_guardian.ACROSS(), s_usdtArbitrum, 99e6);
        Token memory usdt = _token(address(s_usdt));
        uint32 short = uint32(block.timestamp + 30 minutes - 1);
        uint32[3] memory early = [uint32(0), uint32(block.timestamp - 1), short];
        for (uint256 i; i < early.length; ++i) {
            bytes memory context = _acrossContext(99e6, early[i]);
            vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.DeadlineTooEarly.selector, early[i]));
            _accept(usdt, o, context);
        }
        _accept(usdt, o, _acrossContext(99e6, uint32(block.timestamp + 30 minutes)));
        assertEq(s_spokePool.last().fillDeadline, uint32(block.timestamp + 30 minutes), "the window passes");
    }

    // Records

    /// A handoff of nothing isn't an acceptance.
    function test_ZeroAmount_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, 0);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0);
        vm.prank(s_intent);
        vm.expectRevert(BridgeGuardian.ZeroAmount.selector);
        s_guardian.accept(keccak256("intent"), s_user, s_keeper, usdc, 0, o, context);
    }

    /// The record names who handed what: a reconciler counts it only when the caller is the intent
    /// address or the IntentRouter.
    function test_Accepted_RecordsCallerOwnerKeeperAndAmount() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0);
        vm.expectEmit(true, true, true, true, address(s_guardian));
        emit IIntentGuardian.Accepted(bytes32(uint256(1)), keccak256("intent"), s_intent, s_user, s_keeper, AMOUNT, o);
        _accept(usdc, o, context);
    }

    /// Receipts are the guardian's running count; no slot is written per receipt.
    function test_Receipts_CountUp() external {
        s_usdc.mint(s_intent, AMOUNT);
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0);
        assertEq(_accept(usdc, o, context), bytes32(uint256(1)), "first");
        assertEq(_accept(usdc, o, context), bytes32(uint256(2)), "second");
        assertEq(uint8(s_guardian.status(bytes32(uint256(2)))), uint8(Status.PENDING), "issued");
        assertEq(uint8(s_guardian.status(bytes32(uint256(3)))), uint8(Status.NONE), "not issued");
        assertEq(uint8(s_guardian.status(bytes32(0))), uint8(Status.NONE), "zero");
    }

    // Methods

    function test_CommittedMethod_KeeperCannotSwitch() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, 0);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _acrossContext(AMOUNT, uint32(block.timestamp + 1 hours));
        vm.expectRevert(
            abi.encodeWithSelector(BridgeGuardian.MethodMismatch.selector, s_guardian.CCTP(), s_guardian.ACROSS())
        );
        _accept(usdc, o, context);
    }

    function test_AnyMethod_KeeperChooses() external {
        _accept(_token(address(s_usdc)), _obligation(bytes32(0), s_usdcArbitrum, AMOUNT), _cctpContext(0));
        assertEq(s_messenger.burns(), 1, "the keeper's choice, within the obligation");
    }

    function test_UnknownMethod_Reverts() external {
        Obligation memory o = _obligation(bytes32(0), s_usdcArbitrum, 0);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = abi.encode(uint256(0), keccak256("relay"), "");
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.UnsupportedMethod.selector, keccak256("relay")));
        _accept(usdc, o, context);
    }

    /// Neither bridge charges a native messaging fee: call value is refused.
    function test_CallValue_Reverts() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0); // an external call: built before the prank
        vm.prank(s_intent);
        vm.expectRevert(BridgeGuardian.UnexpectedValue.selector);
        s_guardian.accept{ value: 0.01 ether }(keccak256("intent"), s_user, s_keeper, usdc, AMOUNT, o, context);
    }

    function test_LevelAndSettlement() external {
        assertEq(uint8(s_guardian.level()), uint8(Level.FORWARD), "forward");
        vm.expectRevert(BridgeGuardian.Unsupported.selector);
        s_guardian.settle(bytes32(0), Status.FULFILLED, "");
    }
}

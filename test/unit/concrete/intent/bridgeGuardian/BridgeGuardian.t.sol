// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../../../../../src/intent/BridgeGuardian.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Level, Obligation, Status } from "../../../../../src/interfaces/IIntentGuardian.sol";
import { IAcrossSpokePool } from "../../../../../src/interfaces/bridges/IAcrossSpokePool.sol";
import { ITokenMessengerV2 } from "../../../../../src/interfaces/bridges/ITokenMessengerV2.sol";
import { MockAcrossSpokePool, MockTokenMessengerV2 } from "../../../../mocks/MockBridges.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";

contract BridgeGuardian_Unit_Concrete_Test is Test {
    uint256 internal constant AMOUNT = 100e6;
    uint256 internal constant ARBITRUM = 42_161;
    uint32 internal constant ARBITRUM_DOMAIN = 3;

    address internal s_intent = makeAddr("Intent"); // the caller: an intent address or a router
    address internal s_user = makeAddr("User");
    address internal s_usdcArbitrum = makeAddr("USDC on Arbitrum");
    address internal s_usdtArbitrum = makeAddr("USDT on Arbitrum");

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
        s_guardian = new BridgeGuardian(
            ITokenMessengerV2(address(s_messenger)),
            address(s_usdc),
            destinations,
            IAcrossSpokePool(address(s_spokePool))
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
        return abi.encode(s_guardian.CCTP(), abi.encode(maxFee, uint32(1000)));
    }

    function _acrossContext(uint256 outputAmount, uint32 fillDeadline) internal view returns (bytes memory) {
        return abi.encode(s_guardian.ACROSS(), abi.encode(outputAmount, address(0), fillDeadline, uint32(0)));
    }

    function _accept(Token memory token, Obligation memory o, bytes memory context) internal returns (bytes32) {
        vm.prank(s_intent);
        return s_guardian.accept(keccak256("intent"), token, AMOUNT, o, context);
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
        bytes memory context = abi.encode(keccak256("relay"), "");
        vm.expectRevert(abi.encodeWithSelector(BridgeGuardian.UnsupportedMethod.selector, keccak256("relay")));
        _accept(usdc, o, context);
    }

    function test_CallValue_ReturnsToTheCaller() external {
        Obligation memory o = _obligation(s_guardian.CCTP(), s_usdcArbitrum, AMOUNT);
        Token memory usdc = _token(address(s_usdc));
        bytes memory context = _cctpContext(0); // an external call: built before the prank
        vm.prank(s_intent);
        s_guardian.accept{ value: 0.01 ether }(keccak256("intent"), usdc, AMOUNT, o, context);
        assertEq(s_intent.balance, 1 ether, "returned");
        assertEq(address(s_guardian).balance, 0, "nothing rests");
    }

    function test_LevelAndSettlement() external {
        assertEq(uint8(s_guardian.level()), uint8(Level.FORWARD), "forward");
        vm.expectRevert(BridgeGuardian.Unsupported.selector);
        s_guardian.settle(bytes32(0), Status.FULFILLED, "");
    }
}

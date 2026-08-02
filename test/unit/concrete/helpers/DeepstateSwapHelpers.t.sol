// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../../../../src/EnsoShortcuts.sol";
import { DeepstateSwapHelpers } from "../../../../src/helpers/DeepstateSwapHelpers.sol";
import { IDeepstateV1 } from "../../../../src/interfaces/IDeepstateV1.sol";
import { Token, TokenType } from "../../../../src/interfaces/IEnsoRouter.sol";
import { EnsoRouter } from "../../../../src/router/EnsoRouter.sol";
import { MockERC20 } from "../../../mocks/MockERC20.sol";
import { WeirollPlanner } from "../../../utils/WeirollPlanner.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDeepstateV1 is IDeepstateV1 {
    using SafeERC20 for IERC20;

    IERC20 internal constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    error FillFailed();
    error NativeTransferFailed();

    IERC20 public tokenIn;
    IERC20 public tokenOut;
    uint256 public inputSpent;
    uint256 public outputAmount;
    uint256 public callCount;
    uint256 public receivedValue;
    bytes32 public routeHash;
    bool public allNoRest;
    bool public firstFillOrKill;
    bool public shouldRevert;

    function configure(IERC20 tokenIn_, IERC20 tokenOut_, uint256 inputSpent_, uint256 outputAmount_) external {
        tokenIn = tokenIn_;
        tokenOut = tokenOut_;
        inputSpent = inputSpent_;
        outputAmount = outputAmount_;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function fillRoute(FillParams[] calldata fills) external payable {
        if (shouldRevert) {
            revert FillFailed();
        }

        ++callCount;
        receivedValue = msg.value;
        routeHash = keccak256(abi.encode(fills));
        allNoRest = fills.length != 0;
        firstFillOrKill = fills.length != 0 && fills[0].fillOrKill;
        for (uint256 i; i < fills.length;) {
            allNoRest = allNoRest && fills[i].noRest;
            unchecked {
                ++i;
            }
        }

        if (tokenIn == _ETH) {
            _sendNative(msg.sender, msg.value - inputSpent);
        } else if (inputSpent != 0) {
            tokenIn.safeTransferFrom(msg.sender, address(this), inputSpent);
        }

        if (outputAmount != 0) {
            if (tokenOut == _ETH) {
                _sendNative(msg.sender, outputAmount);
            } else {
                tokenOut.safeTransfer(msg.sender, outputAmount);
            }
        }
    }

    function _sendNative(address receiver, uint256 amount) private {
        (bool success,) = receiver.call{ value: amount }("");
        if (!success) {
            revert NativeTransferFailed();
        }
    }

    receive() external payable { }
}

contract RejectNative {
    receive() external payable {
        revert();
    }
}

contract DeepstateSwapHelpersTest is Test {
    IERC20 internal constant _ETH = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address internal constant RECEIVER = address(0xBEEF);

    DeepstateSwapHelpers internal helper;
    MockDeepstateV1 internal deepstate;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    EnsoRouter internal router;
    EnsoShortcuts internal shortcuts;

    function setUp() public {
        helper = new DeepstateSwapHelpers();
        deepstate = new MockDeepstateV1();
        tokenIn = new MockERC20("Input", "IN");
        tokenOut = new MockERC20("Output", "OUT");
        router = new EnsoRouter();
        shortcuts = EnsoShortcuts(payable(router.shortcuts()));
    }

    function test_swap_refundsUnspentERC20ForcesNoRestAndClearsAllowance() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        IDeepstateV1.FillParams[] memory fills = _mockFills();
        uint256 amountOut = helper.swap(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, fills);

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertEq(tokenOut.balanceOf(address(helper)), 0);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
        assertTrue(deepstate.allNoRest());
        assertTrue(deepstate.firstFillOrKill());
        assertEq(deepstate.routeHash(), keccak256(abi.encode(_forcedNoRest(fills))));
    }

    function test_swap_spendsFullERC20Input() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 100 ether, 70 ether);

        uint256 amountOut = helper.swap(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 0);
        assertEq(tokenIn.balanceOf(address(deepstate)), 100 ether);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
    }

    function test_swap_refundsUnspentNativeInput() public {
        vm.deal(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        deepstate.configure(_ETH, tokenOut, 60 ether, 70 ether);

        uint256 amountOut =
            helper.swap{ value: 100 ether }(deepstate, _ETH, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(RECEIVER.balance, 40 ether);
        assertEq(address(deepstate).balance, 60 ether);
        assertEq(address(helper).balance, 0);
        assertTrue(deepstate.allNoRest());
    }

    function test_swap_supportsNativeOutput() public {
        tokenIn.mint(address(this), 100 ether);
        tokenIn.approve(address(helper), 100 ether);
        vm.deal(address(deepstate), 70 ether);
        deepstate.configure(tokenIn, _ETH, 60 ether, 70 ether);

        uint256 amountOut = helper.swap(deepstate, tokenIn, _ETH, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(RECEIVER.balance, 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 60 ether);
        assertEq(address(helper).balance, 0);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
    }

    function test_swap_preservesPreexistingHelperBalances() public {
        tokenIn.mint(address(this), 100 ether);
        tokenIn.mint(address(helper), 11 ether);
        tokenOut.mint(address(helper), 13 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        uint256 amountOut = helper.swap(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(amountOut, 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(address(helper)), 11 ether);
        assertEq(tokenOut.balanceOf(address(helper)), 13 ether);
    }

    function test_swap_engineRevertIsAtomic() public {
        tokenIn.mint(address(this), 100 ether);
        tokenIn.approve(address(helper), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);
        deepstate.setShouldRevert(true);

        vm.expectRevert(MockDeepstateV1.FillFailed.selector);
        helper.swap(deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(tokenIn.balanceOf(address(this)), 100 ether);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertEq(tokenIn.balanceOf(address(deepstate)), 0);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
        assertEq(deepstate.callCount(), 0);
    }

    function test_swap_eoaEngineCannotReceiveNativeInput() public {
        address eoaEngine = address(0xCAFE);
        vm.deal(address(this), 100 ether);

        vm.expectRevert();
        helper.swap{ value: 100 ether }(IDeepstateV1(eoaEngine), _ETH, tokenOut, 100 ether, RECEIVER, _mockFills());

        assertEq(eoaEngine.balance, 0);
        assertEq(address(helper).balance, 0);
    }

    function test_swap_failedNativeForwardIsAtomic() public {
        RejectNative receiver = new RejectNative();
        tokenIn.mint(address(this), 100 ether);
        tokenIn.approve(address(helper), 100 ether);
        vm.deal(address(deepstate), 70 ether);
        deepstate.configure(tokenIn, _ETH, 60 ether, 70 ether);

        vm.expectRevert(abi.encodeWithSelector(DeepstateSwapHelpers.TransferFailed.selector, address(receiver)));
        helper.swap(deepstate, tokenIn, _ETH, 100 ether, address(receiver), _mockFills());

        assertEq(tokenIn.balanceOf(address(this)), 100 ether);
        assertEq(tokenIn.balanceOf(address(deepstate)), 0);
        assertEq(address(deepstate).balance, 70 ether);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
    }

    function test_swap_rejectsInvalidEnvelope() public {
        IDeepstateV1.FillParams[] memory fills = _mockFills();
        IDeepstateV1.FillParams[] memory empty = new IDeepstateV1.FillParams[](0);

        vm.expectRevert(DeepstateSwapHelpers.InvalidEngine.selector);
        helper.swap(IDeepstateV1(address(0)), tokenIn, tokenOut, 0, RECEIVER, fills);

        vm.expectRevert(DeepstateSwapHelpers.InvalidReceiver.selector);
        helper.swap(deepstate, tokenIn, tokenOut, 0, address(0), fills);

        vm.expectRevert(DeepstateSwapHelpers.InvalidToken.selector);
        helper.swap(deepstate, IERC20(address(0)), tokenOut, 0, RECEIVER, fills);

        vm.expectRevert(DeepstateSwapHelpers.InvalidToken.selector);
        helper.swap(deepstate, tokenIn, IERC20(address(0)), 0, RECEIVER, fills);

        vm.expectRevert(DeepstateSwapHelpers.InvalidPair.selector);
        helper.swap(deepstate, tokenIn, tokenIn, 0, RECEIVER, fills);

        vm.expectRevert(DeepstateSwapHelpers.InvalidRoute.selector);
        helper.swap(deepstate, tokenIn, tokenOut, 0, RECEIVER, empty);
    }

    function test_swap_rejectsIncorrectNativeValue() public {
        vm.deal(address(this), 2 ether);

        vm.expectRevert(abi.encodeWithSelector(DeepstateSwapHelpers.IncorrectValue.selector, 1 ether, 2 ether));
        helper.swap{ value: 2 ether }(deepstate, _ETH, tokenOut, 1 ether, RECEIVER, _mockFills());
    }

    function test_swap_rejectsValueWithERC20Input() public {
        vm.deal(address(this), 1);

        vm.expectRevert(abi.encodeWithSelector(DeepstateSwapHelpers.IncorrectValue.selector, 0, 1));
        helper.swap{ value: 1 }(deepstate, tokenIn, tokenOut, 0, RECEIVER, _mockFills());
    }

    function test_swap_executesThroughUnmodifiedEnsoRouter() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(router), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](3);
        commands[0] =
            WeirollPlanner.buildCommand(tokenIn.approve.selector, 0x01, 0x0001ffffffff, 0xff, address(tokenIn));
        commands[1] = WeirollPlanner.buildCommand(helper.swap.selector, 0x21, 0x02ffffffffff, 0xff, address(helper));
        state[0] = abi.encode(address(helper));
        state[1] = abi.encode(100 ether);
        state[2] = abi.encodeCall(helper.swap, (deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills()));

        bytes memory data = abi.encodeCall(shortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));
        Token memory routeInput = Token(TokenType.ERC20, abi.encode(address(tokenIn), 100 ether));
        Token memory routeOutput = Token(TokenType.ERC20, abi.encode(address(tokenOut), 70 ether));

        router.safeRouteSingle(routeInput, routeOutput, RECEIVER, data);

        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(tokenIn.balanceOf(RECEIVER), 40 ether);
        assertEq(tokenIn.balanceOf(address(shortcuts)), 0);
        assertEq(tokenOut.balanceOf(address(shortcuts)), 0);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertEq(tokenOut.balanceOf(address(helper)), 0);
        assertEq(tokenIn.allowance(address(shortcuts), address(helper)), 0);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
        assertTrue(deepstate.allNoRest());
    }

    function test_swap_ensoRouterMinimumOutputRevertsAtomically() public {
        tokenIn.mint(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        tokenIn.approve(address(router), 100 ether);
        deepstate.configure(tokenIn, tokenOut, 60 ether, 70 ether);

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](3);
        commands[0] =
            WeirollPlanner.buildCommand(tokenIn.approve.selector, 0x01, 0x0001ffffffff, 0xff, address(tokenIn));
        commands[1] = WeirollPlanner.buildCommand(helper.swap.selector, 0x21, 0x02ffffffffff, 0xff, address(helper));
        state[0] = abi.encode(address(helper));
        state[1] = abi.encode(100 ether);
        state[2] = abi.encodeCall(helper.swap, (deepstate, tokenIn, tokenOut, 100 ether, RECEIVER, _mockFills()));

        bytes memory data = abi.encodeCall(shortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));
        Token memory routeInput = Token(TokenType.ERC20, abi.encode(address(tokenIn), 100 ether));
        Token memory routeOutput = Token(TokenType.ERC20, abi.encode(address(tokenOut), 71 ether));

        vm.expectRevert(abi.encodeWithSelector(EnsoRouter.AmountTooLow.selector, routeOutput, 70 ether, 71 ether));
        router.safeRouteSingle(routeInput, routeOutput, RECEIVER, data);

        assertEq(tokenIn.balanceOf(address(this)), 100 ether);
        assertEq(tokenOut.balanceOf(RECEIVER), 0);
        assertEq(tokenIn.balanceOf(RECEIVER), 0);
        assertEq(tokenOut.balanceOf(address(deepstate)), 70 ether);
        assertEq(deepstate.callCount(), 0);
    }

    function test_swap_executesNativeInputThroughUnmodifiedEnsoRouter() public {
        vm.deal(address(this), 100 ether);
        tokenOut.mint(address(deepstate), 70 ether);
        deepstate.configure(_ETH, tokenOut, 60 ether, 70 ether);

        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](2);
        commands[0] = WeirollPlanner.buildCommand(helper.swap.selector, 0x23, 0x0001ffffffff, 0xff, address(helper));
        state[0] = abi.encode(100 ether);
        state[1] = abi.encodeCall(helper.swap, (deepstate, _ETH, tokenOut, 100 ether, RECEIVER, _mockFills()));

        bytes memory data = abi.encodeCall(shortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));
        Token memory routeInput = Token(TokenType.Native, abi.encode(100 ether));
        Token memory routeOutput = Token(TokenType.ERC20, abi.encode(address(tokenOut), 70 ether));

        router.safeRouteSingle{ value: 100 ether }(routeInput, routeOutput, RECEIVER, data);

        assertEq(tokenOut.balanceOf(RECEIVER), 70 ether);
        assertEq(RECEIVER.balance, 40 ether);
        assertEq(address(shortcuts).balance, 0);
        assertEq(address(helper).balance, 0);
        assertEq(address(deepstate).balance, 60 ether);
    }

    function testFuzz_swap_conservesERC20Deltas(uint96 amountIn, uint96 inputSpent, uint96 outputAmount) public {
        vm.assume(amountIn != 0);
        inputSpent = uint96(bound(inputSpent, 0, amountIn));

        tokenIn.mint(address(this), amountIn);
        tokenOut.mint(address(deepstate), outputAmount);
        tokenIn.approve(address(helper), amountIn);
        deepstate.configure(tokenIn, tokenOut, inputSpent, outputAmount);

        uint256 amountOut = helper.swap(deepstate, tokenIn, tokenOut, amountIn, RECEIVER, _mockFills());

        assertEq(amountOut, outputAmount);
        assertEq(tokenOut.balanceOf(RECEIVER), outputAmount);
        assertEq(tokenIn.balanceOf(RECEIVER), uint256(amountIn) - inputSpent);
        assertEq(tokenIn.balanceOf(address(deepstate)), inputSpent);
        assertEq(tokenIn.balanceOf(address(helper)), 0);
        assertEq(tokenOut.balanceOf(address(helper)), 0);
        assertEq(tokenIn.allowance(address(helper), address(deepstate)), 0);
    }

    function _mockFills() internal view returns (IDeepstateV1.FillParams[] memory fills) {
        fills = new IDeepstateV1.FillParams[](2);
        fills[0] = IDeepstateV1.FillParams({
            token0: address(tokenIn),
            token1: address(tokenOut),
            epoch: 7,
            order: bytes32(uint256(1)),
            isBid: true,
            noRest: false,
            fillOrKill: true
        });
        fills[1] = IDeepstateV1.FillParams({
            token0: address(tokenIn),
            token1: address(tokenOut),
            epoch: 8,
            order: bytes32(uint256(2)),
            isBid: false,
            noRest: false,
            fillOrKill: false
        });
    }

    function _forcedNoRest(IDeepstateV1.FillParams[] memory fills)
        internal
        pure
        returns (IDeepstateV1.FillParams[] memory)
    {
        for (uint256 i; i < fills.length;) {
            fills[i].noRest = true;
            unchecked {
                ++i;
            }
        }
        return fills;
    }
}

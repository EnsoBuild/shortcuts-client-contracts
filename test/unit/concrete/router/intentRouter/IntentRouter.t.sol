// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { AbstractEnsoShortcuts } from "../../../../../src/AbstractEnsoShortcuts.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent, KeeperFee } from "../../../../../src/interfaces/IIntentRouter.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { WeirollPlanner } from "../../../../utils/WeirollPlanner.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

abstract contract IntentRouter_Unit_Concrete_Test is Test {
    uint256 internal constant OWNER_PK = 0xA11CE;

    address payable internal s_owner;
    address payable internal s_keeper;
    address payable internal s_recipient;

    IntentRouter internal s_router;
    address internal s_shortcuts;
    MockERC20 internal s_tokenIn;
    MockERC20 internal s_tokenOut;

    function setUp() public virtual {
        s_owner = payable(vm.addr(OWNER_PK));
        vm.label(s_owner, "Owner");

        s_keeper = payable(vm.addr(2));
        vm.deal(s_keeper, 100 ether);
        vm.label(s_keeper, "Keeper");

        s_recipient = payable(vm.addr(3));
        vm.label(s_recipient, "Recipient");

        s_router = new IntentRouter(s_keeper);
        vm.label(address(s_router), "IntentRouter");
        s_shortcuts = s_router.shortcuts();
        vm.label(s_shortcuts, "EnsoShortcuts");

        s_tokenIn = new MockERC20("TokenIn", "TIN");
        s_tokenIn.mint(s_owner, 1000 ether);
        vm.prank(s_owner);
        s_tokenIn.approve(address(s_router), type(uint256).max);
        vm.label(address(s_tokenIn), "TokenIn");

        s_tokenOut = new MockERC20("TokenOut", "TOUT");
        s_tokenOut.mint(s_shortcuts, 1_000_000 ether); // route inventory
        vm.label(address(s_tokenOut), "TokenOut");
    }

    function _erc20(address token, uint256 amount) internal pure returns (Token memory) {
        return Token({ tokenType: TokenType.ERC20, data: abi.encode(token, amount) });
    }

    function _native(uint256 amount) internal pure returns (Token memory) {
        return Token({ tokenType: TokenType.Native, data: abi.encode(amount) });
    }

    function _fee(address token, uint256 intentFee, uint256 refundFee) internal pure returns (KeeperFee memory) {
        return KeeperFee({ token: token, intentFee: intentFee, refundFee: refundFee });
    }

    function _intent() internal view returns (Intent memory intent) {
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = _erc20(address(s_tokenIn), 100 ether);
        Token[] memory tokensOut = new Token[](1);
        tokensOut[0] = _erc20(address(s_tokenOut), 50 ether);
        intent = Intent({
            version: 1,
            chainId: block.chainid,
            nonce: 0,
            start: uint64(block.timestamp),
            deadline: uint64(block.timestamp + 1 days),
            owner: s_owner,
            recipient: s_recipient,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            keeperFee: _fee(address(0), 0, 0),
            route: ""
        });
    }

    function _sign(Intent memory intent) internal view returns (bytes memory) {
        return _sign(OWNER_PK, intent);
    }

    function _sign(uint256 pk, Intent memory intent) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, s_router.hash(intent));
        return abi.encodePacked(r, s, v);
    }

    function _execute(Intent memory intent, bytes memory route) internal returns (bytes memory) {
        return _execute(intent, _sign(intent), route);
    }

    function _execute(Intent memory intent, bytes memory signature, bytes memory route)
        internal
        returns (bytes memory)
    {
        vm.prank(s_keeper);
        return s_router.execute(intent, signature, route);
    }

    /// Shortcut data: `token.transfer(to, amount)` from the shortcuts contract.
    function _transferRoute(address token, address to, uint256 amount) internal pure returns (bytes memory) {
        bytes32[] memory commands = new bytes32[](1);
        bytes[] memory state = new bytes[](2);
        commands[0] = WeirollPlanner.buildCommand(IERC20.transfer.selector, 0x01, 0x0001ffffffff, 0xff, token);
        state[0] = abi.encode(to);
        state[1] = abi.encode(amount);
        return _shortcut(commands, state);
    }

    function _shortcut(bytes32[] memory commands, bytes[] memory state) internal pure returns (bytes memory) {
        return abi.encodeCall(AbstractEnsoShortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));
    }
}

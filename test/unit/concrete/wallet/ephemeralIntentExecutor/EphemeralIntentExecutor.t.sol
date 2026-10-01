// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent, KeeperFee } from "../../../../../src/interfaces/IIntent.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockIntentRouter } from "../../../../mocks/MockIntentRouter.sol";
import { Test } from "forge-std/Test.sol";

abstract contract EphemeralIntentExecutor_Unit_Concrete_Test is Test {
    address payable internal s_user;
    address payable internal s_keeper;
    address payable internal s_recipient;

    MockIntentRouter internal s_router;
    EphemeralFactory internal s_factory;
    MockERC20 internal s_tokenIn;
    MockERC20 internal s_tokenOut;

    function setUp() public virtual {
        s_user = payable(vm.addr(1));
        vm.label(s_user, "User");

        s_keeper = payable(vm.addr(2));
        vm.deal(s_keeper, 100 ether);
        vm.label(s_keeper, "Keeper");

        s_recipient = payable(vm.addr(3));
        vm.label(s_recipient, "Recipient");

        s_router = new MockIntentRouter();
        vm.label(address(s_router), "MockIntentRouter");

        s_factory = new EphemeralFactory(address(s_router));
        vm.label(address(s_factory), "EphemeralFactory");

        s_tokenIn = new MockERC20("TokenIn", "TIN");
        vm.label(address(s_tokenIn), "TokenIn");

        s_tokenOut = new MockERC20("TokenOut", "TOUT");
        s_tokenOut.mint(address(s_router), 1_000_000 ether); // router inventory
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

    /// A committed-route intent: the shortcut bytes are fixed in the blob, no outcome floor.
    function _intent() internal view returns (Intent memory intent) {
        Token[] memory tokensIn = new Token[](1);
        tokensIn[0] = _erc20(address(s_tokenIn), 100 ether);
        intent = Intent({
            version: 1,
            chainId: block.chainid,
            nonce: 0,
            start: uint64(block.timestamp),
            deadline: uint64(block.timestamp + 1 days),
            owner: s_user,
            recipient: s_recipient,
            keeper: s_keeper,
            keeperFee: _fee(address(0), 0, 0),
            tokensIn: tokensIn,
            tokensOut: new Token[](0),
            route: hex"deadbeef"
        });
    }

    /// A keeper-routed intent: no committed route, one tokenOut minimum at the recipient.
    function _constrainedIntent(uint256 minAmountOut) internal view returns (Intent memory intent) {
        intent = _intent();
        intent.route = "";
        Token[] memory tokensOut = new Token[](1);
        tokensOut[0] = _erc20(address(s_tokenOut), minAmountOut);
        intent.tokensOut = tokensOut;
    }

    function _fund(Intent memory intent, uint256 amount) internal returns (address predicted) {
        predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, amount);
    }

    function _execute(Intent memory intent, bytes memory route) internal returns (address) {
        vm.prank(s_keeper);
        return s_factory.executeIntent(intent, route, new Token[](0));
    }
}

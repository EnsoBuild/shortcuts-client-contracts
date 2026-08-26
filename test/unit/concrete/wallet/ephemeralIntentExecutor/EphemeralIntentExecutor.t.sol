// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Constrained, Intent, Mode } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
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

    function _intent() internal view returns (Intent memory intent) {
        Token[] memory triggers = new Token[](1);
        triggers[0] = _erc20(address(s_tokenIn), 100 ether);
        intent = Intent({
            version: 1,
            chainId: block.chainid,
            nonce: 0,
            start: uint64(block.timestamp),
            deadline: uint64(block.timestamp + 1 days),
            refundRecipient: s_user,
            triggers: triggers,
            keeperFee: _native(0),
            mode: Mode.ROUTE,
            payload: hex"deadbeef"
        });
    }

    function _constrainedIntent(
        uint256 minAmountOut,
        address exclusiveKeeper,
        uint64 exclusiveUntil
    )
        internal
        view
        returns (Intent memory intent)
    {
        intent = _intent();
        intent.mode = Mode.CONSTRAINED;
        Token[] memory tokensOut = new Token[](1);
        tokensOut[0] = _erc20(address(s_tokenOut), minAmountOut);
        intent.payload = abi.encode(
            Constrained({
                recipient: s_recipient,
                tokensOut: tokensOut,
                exclusiveKeeper: exclusiveKeeper,
                exclusiveUntil: exclusiveUntil
            })
        );
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

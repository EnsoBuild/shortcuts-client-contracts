// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token, TokenType } from "../../../../../src/libraries/TokenLib.sol";
import { Intent, Mode } from "../../../../../src/wallet/EphemeralIntentExecutor.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { MockIntentRouter } from "../../../../mocks/MockIntentRouter.sol";
import { Test } from "forge-std/Test.sol";

abstract contract EphemeralFactory_Unit_Concrete_Test is Test {
    address payable internal s_user;
    address payable internal s_keeper;

    MockIntentRouter internal s_router;
    EphemeralFactory internal s_factory;
    MockERC20 internal s_tokenIn;

    function setUp() public virtual {
        s_user = payable(vm.addr(1));
        vm.label(s_user, "User");

        s_keeper = payable(vm.addr(2));
        vm.deal(s_keeper, 100 ether);
        vm.label(s_keeper, "Keeper");

        s_router = new MockIntentRouter();
        vm.label(address(s_router), "MockIntentRouter");

        s_factory = new EphemeralFactory(address(s_router));
        vm.label(address(s_factory), "EphemeralFactory");

        s_tokenIn = new MockERC20("TokenIn", "TIN");
        vm.label(address(s_tokenIn), "TokenIn");
    }

    function _intent() internal view returns (Intent memory intent) {
        Token[] memory triggers = new Token[](1);
        triggers[0] = Token({ tokenType: TokenType.ERC20, data: abi.encode(address(s_tokenIn), uint256(100 ether)) });
        intent = Intent({
            version: 1,
            chainId: block.chainid,
            nonce: 0,
            start: uint64(block.timestamp),
            deadline: uint64(block.timestamp + 1 days),
            refundRecipient: s_user,
            triggers: triggers,
            keeperFee: Token({ tokenType: TokenType.Native, data: abi.encode(uint256(0)) }),
            mode: Mode.ROUTE,
            payload: hex"deadbeef"
        });
    }

    function _fund(Intent memory intent, uint256 amount) internal returns (address predicted) {
        predicted = s_factory.getAddress(intent);
        s_tokenIn.mint(predicted, amount);
    }
}

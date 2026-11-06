// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Codes, Constraints, Intent, Lifetime } from "../../../../../src/interfaces/IIntent.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { MockConstraintRouter } from "../../../../mocks/MockConstraintRouter.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { IntentFixtures } from "../../../../utils/IntentFixtures.sol";

abstract contract IntentRouter_Unit_Concrete_Test is IntentFixtures {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant AMOUNT = 100 ether;
    uint256 internal constant FEE = 1 ether;

    address payable internal s_owner;
    address payable internal s_keeper;
    address payable internal s_stranger;

    IntentRouter internal s_intentRouter;
    MockConstraintRouter internal s_router;
    MockERC20 internal s_tokenIn;
    MockERC20 internal s_tokenOut;

    function setUp() public virtual {
        s_owner = payable(vm.addr(OWNER_PK));
        vm.label(s_owner, "Owner");
        s_keeper = payable(vm.addr(2));
        vm.deal(s_keeper, 100 ether);
        vm.label(s_keeper, "Keeper");
        s_stranger = payable(vm.addr(3));
        vm.label(s_stranger, "Stranger");

        s_intentRouter = new IntentRouter();
        vm.label(address(s_intentRouter), "IntentRouter");
        s_router = new MockConstraintRouter();
        vm.label(address(s_router), "Router");

        s_tokenIn = new MockERC20("TokenIn", "TIN");
        s_tokenIn.mint(s_owner, 1000 ether);
        vm.prank(s_owner);
        s_tokenIn.approve(address(s_intentRouter), type(uint256).max);
        s_tokenOut = new MockERC20("TokenOut", "TOUT");
        s_tokenOut.mint(address(s_router), 1_000_000 ether);
    }

    /// A signed swap of exactly AMOUNT (fee included), floor 2 TOUT per TIN consumed, once.
    function _swapIntent(uint8 consume) internal view returns (Intent memory intent) {
        Constraints memory c =
            _swap(address(s_router), address(s_tokenIn), address(s_tokenOut), AMOUNT, 2e18, FEE, 0, consume);
        c.lifetime = Lifetime({ kind: Codes.ONCE, interval: 0, count: 0 });
        intent = _intent(c, s_owner, s_keeper);
        intent.nonce = 7;
    }

    function _sign(Intent memory intent) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, s_intentRouter.hash(intent));
        return abi.encodePacked(r, s, v);
    }

    function _routes(bytes memory data) internal pure returns (bytes[] memory routes) {
        routes = new bytes[](1);
        routes[0] = data;
    }

    function _exec(address caller, Intent memory intent, bytes memory signature) internal {
        vm.prank(caller);
        s_intentRouter.executeIntent(intent, signature, address(0), _routes(hex"c0ffee"), new bytes[](0));
    }
}

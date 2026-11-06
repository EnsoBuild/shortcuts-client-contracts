// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Execution } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Intent } from "../../../../../src/interfaces/IIntent.sol";
import { IntentHash } from "../../../../../src/libraries/IntentHash.sol";
import { MockConstraintRouter } from "../../../../mocks/MockConstraintRouter.sol";
import { MockERC20 } from "../../../../mocks/MockERC20.sol";
import { IntentFixtures } from "../../../../utils/IntentFixtures.sol";

abstract contract EphemeralIntentExecutor_Unit_Concrete_Test is IntentFixtures {
    address payable internal s_user;
    address payable internal s_keeper;
    address payable internal s_stranger;

    MockConstraintRouter internal s_router;
    EphemeralFactory internal s_factory;
    MockERC20 internal s_tokenIn;
    MockERC20 internal s_tokenOut;

    function setUp() public virtual {
        s_user = payable(vm.addr(1));
        vm.label(s_user, "User");
        s_keeper = payable(vm.addr(2));
        vm.deal(s_keeper, 100 ether);
        vm.label(s_keeper, "Keeper");
        s_stranger = payable(vm.addr(3));
        vm.label(s_stranger, "Stranger");

        s_router = new MockConstraintRouter();
        vm.label(address(s_router), "Router");
        s_factory = new EphemeralFactory();
        vm.label(address(s_factory), "EphemeralFactory");

        s_tokenIn = new MockERC20("TokenIn", "TIN");
        vm.label(address(s_tokenIn), "TokenIn");
        s_tokenOut = new MockERC20("TokenOut", "TOUT");
        s_tokenOut.mint(address(s_router), 1_000_000 ether);
        vm.label(address(s_tokenOut), "TokenOut");
    }

    /// A tree of one leaf: the root is the leaf and the proof is empty.
    function _root(Intent memory intent) internal pure returns (bytes32) {
        return IntentHash.leaf(intent);
    }

    /// A tree of two leaves (sorted-pair hashing), with each leaf's one-element proof.
    function _pair(
        Intent memory a,
        Intent memory b
    )
        internal
        pure
        returns (bytes32 root, bytes32[] memory proofA, bytes32[] memory proofB)
    {
        bytes32 leafA = IntentHash.leaf(a);
        bytes32 leafB = IntentHash.leaf(b);
        root = leafA < leafB ? keccak256(abi.encode(leafA, leafB)) : keccak256(abi.encode(leafB, leafA));
        proofA = new bytes32[](1);
        proofA[0] = leafB;
        proofB = new bytes32[](1);
        proofB[0] = leafA;
    }

    function _execution(Intent memory intent) internal pure returns (Execution memory e) {
        e.intent = intent;
        e.proof = new bytes32[](0);
        e.routes = new bytes[](0);
        e.contexts = new bytes[](0);
        e.sweep = new Token[](0);
    }

    /// A caller sweep list of one ERC20.
    function _sweepOf(address token) internal pure returns (Token[] memory list) {
        list = new Token[](1);
        list[0] = Token({ tokenType: TokenType.ERC20, data: abi.encode(token, uint256(0)) });
    }

    function _withRoute(Execution memory e, bytes memory data) internal pure returns (Execution memory) {
        e.routes = new bytes[](1);
        e.routes[0] = data;
        return e;
    }

    function _run(address caller, bytes32 root, Execution memory e) internal returns (address executor) {
        vm.prank(caller);
        executor = s_factory.executeIntent(root, e);
    }

    /// Deposit `amount` of tokenIn at the address of `root`.
    function _fund(bytes32 root, uint256 amount) internal returns (address at) {
        at = s_factory.getAddress(root);
        s_tokenIn.mint(at, amount);
    }
}

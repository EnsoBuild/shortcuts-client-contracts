// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {
    Asset,
    Codes,
    Constraints,
    Consume,
    Handoff,
    InputSet,
    Intent,
    Lifetime,
    Param,
    Pattern,
    Predicate,
    Request,
    Rule,
    Source,
    Term,
    View
} from "../../src/interfaces/IIntent.sol";
import { Test } from "forge-std/Test.sol";

/// Builders for version 2 intents. Constraints are assembled field by field, then the canonical
/// fixtures below compose them.
abstract contract IntentFixtures is Test {
    uint16 internal constant NONE = Codes.NONE;

    function _constraints(address router) internal pure returns (Constraints memory c) {
        c.lifetime = Lifetime({ kind: Codes.STANDING, interval: 0, count: 0 });
        c.frame = Codes.FRAME_STRICT;
        c.matching = Codes.MATCH_ALL;
        c.router = router;
        c.accounts = new address[](0);
        c.assets = new Asset[](0);
        c.sources = new Source[](0);
        c.views = new View[](0);
        c.patterns = new Pattern[](0);
        c.inputs = InputSet({
            assets: new uint16[](0),
            minimums: new uint256[](0),
            prices: new uint16[](0),
            refundFees: new uint256[](0),
            threshold: 0
        });
        c.terms = new Term[](0);
        c.handoffs = new Handoff[](0);
        c.consumes = new Consume[](0);
        c.predicates = new Predicate[](0);
        c.rules = new Rule[](0);
    }

    function _intent(Constraints memory c, address owner, address keeper) internal view returns (Intent memory) {
        return Intent({
            version: Codes.VERSION,
            chainId: block.chainid,
            nonce: 0,
            start: uint64(block.timestamp),
            deadline: uint64(block.timestamp + 1 days),
            owner: owner,
            keeper: keeper,
            exclusive: 0,
            constraints: c
        });
    }

    function _erc20(address token) internal view returns (Asset memory) {
        return Asset({ kind: Codes.ERC20, chainId: block.chainid, token: token, id: 0 });
    }

    function _native() internal view returns (Asset memory) {
        return Asset({ kind: Codes.NATIVE, chainId: block.chainid, token: address(0), id: 0 });
    }

    function _term(uint8 op, uint16 a, uint16 b, uint256 value) internal pure returns (Term memory) {
        return Term({ op: op, a: a, b: b, value: value, data: "" });
    }

    function _pred(uint8 cmp, uint16 lhs, uint16 rhs) internal pure returns (Predicate memory) {
        return Predicate({ cmp: cmp, lhs: lhs, rhs: rhs, enforce: Codes.ONCHAIN, source: NONE, group: 0 });
    }

    function _rule(
        uint16[] memory inputs,
        uint16[] memory then,
        uint16 feeAsset,
        uint16 fee,
        uint8 consume
    )
        internal
        pure
        returns (Rule memory)
    {
        return Rule({
            inputs: inputs,
            when: new uint16[](0),
            then: then,
            feeAsset: feeAsset,
            fee: fee,
            consume: consume,
            route: "",
            request: Request({ api: bytes32(0), body: "", params: new Param[](0) })
        });
    }

    function _one(uint16 value) internal pure returns (uint16[] memory list) {
        list = new uint16[](1);
        list[0] = value;
    }

    function _two(uint16 a, uint16 b) internal pure returns (uint16[] memory list) {
        list = new uint16[](2);
        list[0] = a;
        list[1] = b;
    }

    function _inputs(uint16 asset, uint256 minimum, uint256 refundFee) internal pure returns (InputSet memory) {
        uint256[] memory minimums = new uint256[](1);
        minimums[0] = minimum;
        uint256[] memory refundFees = new uint256[](1);
        refundFees[0] = refundFee;
        uint16[] memory prices = new uint16[](1);
        prices[0] = NONE;
        return
            InputSet({ assets: _one(asset), minimums: minimums, prices: prices, refundFees: refundFees, threshold: 1 });
    }

    /// Swap `tokenIn` to `tokenOut` through a keeper route, delivered to the owner, with a floor of
    /// `rate` (WAD) per unit consumed. Assets: 0 tokenIn, 1 tokenOut. Fee `fee` in tokenIn.
    ///   terms: 0 DELTA(out, owner), 1 CONSUMED(in), 2 CONST rate, 3 MUL(1, 2), 4 CONST fee
    function _swap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 minimum,
        uint256 rate,
        uint256 fee,
        uint256 refundFee,
        uint8 consume
    )
        internal
        view
        returns (Constraints memory c)
    {
        c = _constraints(router);
        c.assets = new Asset[](2);
        c.assets[0] = _erc20(tokenIn);
        c.assets[1] = _erc20(tokenOut);
        c.inputs = _inputs(0, minimum, refundFee);
        c.terms = new Term[](5);
        c.terms[0] = _term(Codes.OP_DELTA, 1, Codes.OWNER, 0);
        c.terms[1] = _term(Codes.OP_CONSUMED, 0, 0, 0);
        c.terms[2] = _term(Codes.OP_CONST, 0, 0, rate);
        c.terms[3] = _term(Codes.OP_MUL, 1, 2, 0);
        c.terms[4] = _term(Codes.OP_CONST, 0, 0, fee);
        c.predicates = new Predicate[](1);
        c.predicates[0] = _pred(Codes.CMP_GTE, 0, 3);
        c.rules = new Rule[](1);
        c.rules[0] = fee > 0 ? _rule(_one(0), _one(0), 0, 4, consume) : _rule(_one(0), _one(0), NONE, NONE, consume);
    }

    /// Hand `token` to a guardian for delivery on `chainId`: minimum = consumed − fee, deadline =
    /// now + window. Assets: 0 token here, 1 token there. Sources: 0 guardian.
    ///   terms: 0 CONSUMED(token), 1 CONST fee, 2 SUB(0, 1), 3 NOW, 4 CONST window, 5 ADD(3, 4)
    function _bridge(
        address guardian,
        uint8 level,
        address token,
        uint256 chainId,
        address recipient,
        address refund,
        uint256 minimum,
        uint256 fee
    )
        internal
        view
        returns (Constraints memory c)
    {
        c = _constraints(address(0));
        c.assets = new Asset[](2);
        c.assets[0] = _erc20(token);
        c.assets[1] = Asset({ kind: Codes.ERC20, chainId: chainId, token: token, id: 0 });
        c.sources = new Source[](1);
        c.sources[0] = Source({ kind: Codes.GUARDIAN, target: guardian, config: abi.encode(level) });
        c.inputs = _inputs(0, minimum, 0);
        c.terms = new Term[](6);
        c.terms[0] = _term(Codes.OP_CONSUMED, 0, 0, 0);
        c.terms[1] = _term(Codes.OP_CONST, 0, 0, fee);
        c.terms[2] = _term(Codes.OP_SUB, 0, 1, 0);
        c.terms[3] = _term(Codes.OP_NOW, 0, 0, 0);
        c.terms[4] = _term(Codes.OP_CONST, 0, 0, 6 hours);
        c.terms[5] = _term(Codes.OP_ADD, 3, 4, 0);
        c.handoffs = new Handoff[](1);
        c.handoffs[0] = Handoff({
            source: 0,
            chainId: chainId,
            method: keccak256("cctp"),
            recipient: recipient,
            refund: refund,
            input: 0,
            asset: 1,
            minAmount: 2,
            deadline: 5
        });
        c.predicates = new Predicate[](1);
        c.predicates[0] = _pred(Codes.CMP_ACCEPTED, 0, 0);
        c.rules = new Rule[](1);
        c.rules[0] = _rule(_one(0), _one(0), 0, 1, Codes.DRAIN);
    }
}

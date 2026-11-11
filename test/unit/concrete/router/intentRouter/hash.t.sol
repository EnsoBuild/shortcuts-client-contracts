// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {
    Asset,
    Constraints,
    Consume,
    Fee,
    Handoff,
    Input,
    Intent,
    Lifetime,
    Param,
    Pattern,
    Predicate,
    Refund,
    Request,
    Rule,
    Source,
    Term,
    View
} from "../../../../../src/interfaces/IIntent.sol";
import { IntentHash } from "../../../../../src/libraries/IntentHash.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { Test } from "forge-std/Test.sol";

/// Golden vector from viem's hashStruct / hashTypedData for the intent below, which populates every
/// struct type, with the domain { name: "IntentRouter", version: "2", chainId: 31337,
/// verifyingContract: ROUTER }. It pins every type string and the nested array hashing, so an SDK
/// signing with the same types produces signatures the router accepts. LEAF pins the ABI encoding
/// an ephemeral tree commits to, for the same struct.
contract IntentRouter_Hash_Unit_Concrete_Test is Test {
    address internal constant ROUTER = 0x7777777777777777777777777777777777777777;
    bytes32 internal constant STRUCT_HASH = 0x6192f031d39f70a98eed0d2f8b103e79dbceff4b7554850af774388d8bf44670;
    bytes32 internal constant DIGEST = 0x923aadfbf214b69d1df5c2fc971fb55a576a17e314dde2cb03eecd2edca64d3d;
    /// keccak256(keccak256(abi.encode(intent))), from viem's encodeAbiParameters.
    bytes32 internal constant LEAF = 0x04b1b843a14fc84c333c9f9b418bc31d7f233213b38b0e33045b223de7dac7c9;

    function test_WhenHashedAgainstTheReferenceEncoder() external {
        vm.chainId(31_337);
        deployCodeTo("IntentRouter.sol:IntentRouter", ROUTER);
        Intent memory intent = _intent();

        assertEq(IntentHash.hash(intent), STRUCT_HASH, "struct hash");
        assertEq(IntentRouter(payable(ROUTER)).hash(intent), DIGEST, "digest");
        assertEq(IntentHash.leaf(intent), LEAF, "ephemeral leaf");
    }

    function _intent() internal pure returns (Intent memory intent) {
        Constraints memory c;
        c.lifetime = Lifetime({ kind: 1, interval: 86_400, count: 12 });
        c.frame = 1;
        c.matching = 0;
        c.router = 0x9999999999999999999999999999999999999999;
        c.accounts = new address[](1);
        c.accounts[0] = 0x2222222222222222222222222222222222222222;
        c.assets = new Asset[](2);
        c.assets[0] = Asset({ kind: 1, chainId: 31_337, token: 0x3333333333333333333333333333333333333333, id: 0 });
        c.assets[1] = Asset({ kind: 3, chainId: 42_161, token: 0x5555555555555555555555555555555555555555, id: 9 });
        c.sources = new Source[](1);
        c.sources[0] =
            Source({ kind: 1, target: 0x6666666666666666666666666666666666666666, config: abi.encode(uint8(0)) });
        c.views = new View[](1);
        c.views[0] = View({
            target: 0x7777777777777777777777777777777777777777,
            selector: 0x70a08231,
            args: abi.encode(0x1111111111111111111111111111111111111111),
            word: 0
        });
        bytes32[] memory patternArgs = new bytes32[](2);
        patternArgs[0] = bytes32(uint256(1));
        patternArgs[1] = bytes32(uint256(2));
        c.patterns = new Pattern[](1);
        c.patterns[0] = Pattern({
            kind: 1,
            target: 0x3333333333333333333333333333333333333333,
            sig: bytes32(bytes4(0xa9059cbb)),
            args: patternArgs,
            wildcards: 2
        });
        c.refunds = new Refund[](1);
        c.refunds[0] = Refund({ asset: 0, fee: 0.5 ether });
        c.terms = new Term[](4);
        c.terms[0] = Term({ op: 3, a: 1, b: 1, value: 0, data: "" });
        c.terms[1] = Term({ op: 7, a: 0, b: 0, value: 0, data: "" });
        c.terms[2] = Term({ op: 13, a: 1, b: 0, value: 9900, data: "" });
        c.terms[3] = Term({ op: 6, a: 0, b: 0, value: 0, data: abi.encodePacked(bytes32("buy")) });
        c.handoffs = new Handoff[](1);
        c.handoffs[0] = Handoff({
            source: 0,
            chainId: 42_161,
            method: keccak256("cctp"),
            recipient: 0x2222222222222222222222222222222222222222,
            refund: 0x1111111111111111111111111111111111111111,
            input: 0,
            asset: 1,
            minAmount: 2,
            deadline: 1
        });
        c.consumes = new Consume[](1);
        c.consumes[0] = Consume({ source: 0, key: bytes32("buy"), amount: 1, cap: 150 ether, period: 86_400 });
        c.predicates = new Predicate[](2);
        c.predicates[0] = Predicate({ cmp: 0, lhs: 0, rhs: 2, enforce: 0, source: 65_535, group: 0 });
        c.predicates[1] = Predicate({ cmp: 5, lhs: 0, rhs: 0, enforce: 0, source: 65_535, group: 1 });
        Input[] memory ruleInputs = new Input[](2);
        ruleInputs[0] = Input({ asset: 0, minimum: 100 ether, price: 65_535 });
        ruleInputs[1] = Input({ asset: 1, minimum: 0, price: 0 });
        Fee[] memory fees = new Fee[](2);
        fees[0] = Fee({ asset: 0, amount: 1 });
        fees[1] = Fee({ asset: 1, amount: 0 });
        uint16[] memory then = new uint16[](2);
        then[1] = 1;
        Param[] memory params = new Param[](1);
        params[0] = Param({ name: bytes32("amount"), kind: 2, index: 1 });
        c.rules = new Rule[](1);
        c.rules[0] = Rule({
            inputs: ruleInputs,
            threshold: 2,
            when: new uint16[](0),
            then: then,
            fees: fees,
            consume: 1,
            routing: 1,
            route: hex"deadbeef",
            request: Request({ api: keccak256("enso.bundle.v1"), body: '{"a":"{$amount}"}', params: params })
        });
        intent = Intent({
            version: 2,
            chainId: 31_337,
            nonce: 7,
            start: 1_700_000_000,
            deadline: 1_700_003_600,
            owner: 0x1111111111111111111111111111111111111111,
            keeper: 0x8888888888888888888888888888888888888888,
            exclusive: 1_700_001_800,
            constraints: c
        });
    }
}

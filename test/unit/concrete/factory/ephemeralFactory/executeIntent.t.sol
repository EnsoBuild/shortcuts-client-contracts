// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../../../../../src/factory/EphemeralFactory.sol";
import { Token } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Execution, IEphemeralFactory } from "../../../../../src/interfaces/IEphemeralFactory.sol";
import { Codes, Intent, Lifetime } from "../../../../../src/interfaces/IIntent.sol";
import { IntentRecord } from "../../../../../src/libraries/IntentRecord.sol";
import { EphemeralFactory_Unit_Concrete_Test } from "./EphemeralFactory.t.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";

/// A router whose route re-enters the factory.
contract ReenteringRouter {
    EphemeralFactory internal immutable i_factory;
    bytes32 internal s_root;
    bytes internal s_execution;

    constructor(EphemeralFactory factory) {
        i_factory = factory;
    }

    function arm(bytes32 root, bytes calldata execution) external {
        s_root = root;
        s_execution = execution;
    }

    function routeSingle(Token calldata, bytes calldata) external payable returns (bytes memory) {
        (bool ok, bytes memory ret) = address(i_factory)
            .call(bytes.concat(IEphemeralFactory.executeIntent.selector, abi.encode(s_root), s_execution));
        require(!ok, "re-entry succeeded");
        assembly ("memory-safe") {
            revert(add(ret, 0x20), mload(ret))
        }
    }
}

contract EphemeralFactory_ExecuteIntent_Test is EphemeralFactory_Unit_Concrete_Test {
    function test_EmitsExecuted() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        address at = _fund(root, DEPOSIT);
        s_router.addOut(address(s_tokenOut), 200 ether, s_user);

        vm.expectEmit(address(s_factory));
        emit IEphemeralFactory.Executed(at, root);
        _run(s_keeper, root, _withRoute(_execution(intent), hex"c0ffee"));
    }

    function test_NonCanonicalEncoding_Reverts() external {
        Intent memory intent = _swapIntent();
        bytes32 root = _root(intent);
        bytes memory data = abi.encodeCall(IEphemeralFactory.executeIntent, (root, _execution(intent)));
        // Point the execution's offset somewhere other than directly after the head.
        assembly ("memory-safe") {
            mstore(add(data, 0x44), 0x60)
        }
        vm.prank(s_keeper);
        (bool ok, bytes memory ret) = address(s_factory).call(data);
        assertFalse(ok, "rejected");
        assertEq(bytes4(ret), EphemeralFactory.NonCanonicalEncoding.selector, "reason");
    }

    function test_ContextIsEmptyOutsideAConstruction() external view {
        (bytes memory data, address sender,) = s_factory.context();
        assertEq(data.length, 0, "no execution");
        assertEq(sender, address(0), "no sender");
    }

    function test_ReentryReverts() external {
        ReenteringRouter router = new ReenteringRouter(s_factory);
        Intent memory intent = _swapIntent();
        intent.constraints.router = address(router);
        bytes32 root = _root(intent);
        _fund(root, DEPOSIT);
        Execution memory e = _withRoute(_execution(intent), hex"c0ffee");
        bytes memory encoded = abi.encode(e);
        router.arm(root, encoded);

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _run(s_keeper, root, e);
    }

    function test_Records_AreKeyedByTheWriter() external {
        Lifetime memory once = Lifetime({ kind: Codes.ONCE, interval: 0, count: 0 });
        vm.prank(s_stranger);
        assertEq(s_factory.record(once, uint64(block.timestamp)), IntentRecord.ALLOWED, "first write");
        assertEq(s_factory.verdict(s_stranger, once, uint64(block.timestamp)), IntentRecord.EXHAUSTED, "used");
        assertEq(s_factory.verdict(s_keeper, once, uint64(block.timestamp)), IntentRecord.ALLOWED, "others untouched");
    }
}

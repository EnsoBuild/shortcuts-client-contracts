// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { ChainId } from "../src/libraries/ChainOwner.sol";
import { IntentRouter } from "../src/router/IntentRouter.sol";
import { Script } from "forge-std/Script.sol";

/// Foundry's chain id cheatcode, which this forge-std's Vm doesn't declare.
interface IChainIdCheat {
    function getChainId() external view returns (uint256);
}

/// Deterministic deployment for the intent contracts.
///
/// IntentEvaluator and IntentHash are external libraries. `forge script` deploys them itself, through
/// the standard CREATE2 deployer with a zero salt, so their addresses depend only on their bytecode.
/// The linked addresses end up in the factory's executor creation code, and so in every intent
/// address: one library address everywhere is what makes one deposit address everywhere. Forge falls
/// back to nonce-based library deployment on a chain without the CREATE2 deployer, so each script
/// checks the linked addresses rather than trusting the linker.
///
/// Every deployment is salted CREATE2 through the same deployer and skipped when its address already
/// holds code, so a script can be re-run on a chain that is partly or fully deployed.
abstract contract IntentDeployment is Script {
    string internal constant EVALUATOR = "IntentEvaluator.sol:IntentEvaluator";
    string internal constant HASH = "IntentHash.sol:IntentHash";

    bytes32 internal constant FACTORY_SALT = "EphemeralFactory";
    bytes32 internal constant ROUTER_SALT = "IntentRouter";
    bytes32 internal constant COUNTER_SALT = "IntentCounter";

    /// The selected fork's chain id. Scripts read it here, never as `block.chainid`: with via_ir the
    /// optimizer treats `chainid()` as constant for the whole call and may reuse a value read before
    /// a fork switch. A cheatcode call's result can't be reused that way.
    function _chainId() internal view returns (uint256) {
        return IChainIdCheat(VM_ADDRESS).getChainId();
    }

    function _requireSupported() internal view {
        if (_chainId() == ChainId.ZKSYNC) {
            revert("unsupported chain"); // zkSync's CREATE2 derivation differs
        }
        require(CREATE2_FACTORY.code.length != 0, "no CREATE2 deployer");
    }

    /// The address a library is linked at: CREATE2 through the standard deployer, zero salt.
    function _library(string memory artifact) internal view returns (address) {
        return vm.computeCreate2Address(bytes32(0), keccak256(vm.getCode(artifact)), CREATE2_FACTORY);
    }

    /// Fails unless `lib` is deployed and linked into `creationCode`.
    function _requireLinked(bytes memory creationCode, string memory artifact) internal view returns (address lib) {
        lib = _library(artifact);
        require(_contains(creationCode, lib), string.concat(artifact, " is not linked at its CREATE2 address"));
        require(lib.code.length != 0, string.concat(artifact, " is not deployed"));
    }

    /// Deploys `creationCode` (with any constructor arguments appended) through the standard CREATE2
    /// deployer, unless its address already holds code. The deployer is called directly: forge
    /// doesn't route `new C{ salt: … }` through it on every chain (on OP-stack chains it deploys from
    /// the sender instead).
    function _deploy(bytes32 salt, bytes memory creationCode) internal returns (address deployed) {
        deployed = _predicted(salt, creationCode);
        if (deployed.code.length == 0) {
            vm.broadcast();
            (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(salt, creationCode));
            require(ok, "CREATE2 deployment failed");
        }
        require(deployed.code.length != 0, "not deployed at the CREATE2 address");
    }

    /// The ephemeral factory's address: it takes no constructor arguments.
    function _factory() internal pure returns (address) {
        return _predicted(FACTORY_SALT, type(EphemeralFactory).creationCode);
    }

    /// The IntentRouter's init code: it takes the factory, whose intent lock it shares.
    function _routerCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(IntentRouter).creationCode, abi.encode(_factory()));
    }

    /// Where `_deploy` puts `creationCode`. CREATE2 commits to the init code, so code found here is
    /// this build's code.
    function _predicted(bytes32 salt, bytes memory creationCode) internal pure returns (address) {
        return vm.computeCreate2Address(salt, keccak256(creationCode), CREATE2_FACTORY);
    }

    function _contains(bytes memory code, address lib) private pure returns (bool) {
        bytes20 needle = bytes20(lib);
        for (uint256 i; i + 20 <= code.length; ++i) {
            bytes32 word;
            assembly ("memory-safe") {
                word := mload(add(add(code, 0x20), i))
            }
            if (bytes20(word) == needle) {
                return true;
            }
        }
        return false;
    }
}

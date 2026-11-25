// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { IntentCounter } from "../src/intent/IntentCounter.sol";
import { IIntentGuardian, Level } from "../src/interfaces/IIntentGuardian.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { EphemeralIntentExecutor } from "../src/wallet/EphemeralIntentExecutor.sol";
import { BridgeConfig } from "./BridgeConfig.sol";
import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

interface IShortcutsRouter {
    function shortcuts() external view returns (address);
}

/// Writes deployments.json into the intent SDK, which publishes it: the file its `loadDeployments`
/// reads. The SDK repo is expected next to this one (../enso-intent-sdk).
///
///     COMMIT=$(git rev-parse HEAD) forge script script/IntentDeploymentsWriter.s.sol
///
/// Forks every `rpc_endpoints` entry in foundry.toml and lists a chain only where the ephemeral
/// factory is deployed. Every address but EnsoRouter's is predicted from this build with the
/// deployers' salts, and CREATE2 commits to the init code, so code at a predicted address is this
/// build's code; contracts not deployed on a chain are left out of it. EnsoRouter isn't deployed by
/// these scripts: its per-chain address is listed here and checked on-chain.
contract IntentDeploymentsWriter is BridgeConfig {
    string internal constant OUT = "../enso-intent-sdk/deployments.json";

    function run() public returns (string memory json) {
        bytes memory executorCreationCode = type(EphemeralIntentExecutor).creationCode;
        bytes memory factoryCreationCode = type(EphemeralFactory).creationCode;
        address evaluator = _requireLinked(factoryCreationCode, EVALUATOR);
        address factory = _predicted(FACTORY_SALT, factoryCreationCode);

        Vm.Rpc[] memory rpcs = vm.rpcUrlStructs();
        uint256 listed;
        string memory chains;
        for (uint256 i; i < rpcs.length; ++i) {
            if (!_fork(rpcs[i].url)) {
                console2.log("skipped (no fork):", rpcs[i].key);
                continue;
            }
            uint256 chainId = _chainId();
            if (chainId == ChainId.ZKSYNC || factory.code.length == 0) {
                console2.log("skipped (no factory):", rpcs[i].key);
                continue;
            }
            require(evaluator.code.length != 0, string.concat("no evaluator on ", rpcs[i].key));
            chains = vm.serializeString("chains", vm.toString(chainId), _chain(evaluator));
            ++listed;
            console2.log("listed:", rpcs[i].key, chainId);
        }
        require(listed != 0, "the factory is deployed on no chain");

        vm.serializeUint("deployments", "format", 2);
        vm.serializeString("deployments", "commit", vm.envString("COMMIT"));
        vm.serializeAddress("deployments", "factory", factory);
        vm.serializeBytes("deployments", "executorCreationCode", executorCreationCode);
        vm.serializeBytes32("deployments", "executorCreationCodeHash", keccak256(executorCreationCode));
        json = vm.serializeString("deployments", "chains", chains);
        vm.writeJson(json, OUT);
    }

    /// The selected fork's entry.
    function _chain(address evaluator) internal returns (string memory) {
        uint256 chainId = _chainId();
        string memory key = string.concat("chain-", vm.toString(chainId));
        address ensoRouter = _ensoRouter(chainId);
        require(
            ensoRouter.code.length != 0 && IShortcutsRouter(ensoRouter).shortcuts() != address(0),
            string.concat("no EnsoRouter at the listed address on chain ", vm.toString(chainId))
        );
        vm.serializeAddress(key, "ensoRouter", ensoRouter);
        vm.serializeAddress(key, "evaluator", evaluator);

        address router = _predicted(ROUTER_SALT, _routerCode());
        if (router.code.length != 0) {
            vm.serializeAddress(key, "intentRouter", router);
        }
        address counter = _predicted(COUNTER_SALT, type(IntentCounter).creationCode);
        if (counter.code.length != 0) {
            vm.serializeAddress(key, "counter", counter);
        }

        GuardianConfig memory config = _guardianConfig();
        vm.serializeString(key, "guardians", _guardians(config));
        string memory tokens = "{}";
        if (config.usdc != address(0)) {
            tokens = vm.serializeAddress(string.concat(key, "-tokens"), "USDC", config.usdc);
        }
        return vm.serializeString(key, "tokens", tokens);
    }

    /// The bridge guardian built from this chain's BridgeConfig, when it is deployed.
    function _guardians(GuardianConfig memory config) internal returns (string memory) {
        if (config.tokenMessenger == address(0) && config.spokePool == address(0)) {
            return "{}";
        }
        address guardian = _predicted(GUARDIAN_SALT, _guardianCreationCode(config));
        if (guardian.code.length == 0) {
            return "{}";
        }
        string memory key = string.concat("guardian-", vm.toString(_chainId()));
        vm.serializeAddress(key, "address", guardian);
        vm.serializeString(key, "level", _level(IIntentGuardian(guardian).level()));

        string[] memory methods =
            new string[]((config.tokenMessenger != address(0) ? 1 : 0) + (config.spokePool != address(0) ? 1 : 0));
        uint256 n;
        if (config.tokenMessenger != address(0)) {
            methods[n++] = "cctp";
            string[] memory destinations = new string[](config.destinations.length);
            for (uint256 i; i < destinations.length; ++i) {
                destinations[i] = vm.toString(config.destinations[i].chainId);
            }
            vm.serializeString(key, "cctpDestinations", destinations);
        }
        if (config.spokePool != address(0)) {
            methods[n++] = "across";
        }
        string memory entry = vm.serializeString(key, "methods", methods);
        return vm.serializeString(string.concat(key, "-set"), "bridge", entry);
    }

    /// Selects a fork of `url`; false when the endpoint is unset or unreachable.
    function _fork(string memory url) internal returns (bool) {
        try vm.createSelectFork(url) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _level(Level level) internal pure returns (string memory) {
        if (level == Level.FORWARD) {
            return "FORWARD";
        }
        if (level == Level.BONDED) {
            return "BONDED";
        }
        return "FRONTED";
    }

    /// EnsoRouter on each chain, as the CCIP and LayerZero deployers list it (Katana from the latter;
    /// checked on-chain). `_chain` checks it again.
    function _ensoRouter(uint256 chainId) internal pure returns (address) {
        if (chainId == ChainId.LINEA) {
            return 0xA146d46823f3F594B785200102Be5385CAfCE9B5;
        }
        if (chainId == ChainId.PLUME || chainId == ChainId.KATANA) {
            return 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F;
        }
        if (chainId == ChainId.SEI) {
            return 0x300b3D30aaBf46b05983284f0297D966E92bbeB2;
        }
        if (
            chainId == ChainId.PLASMA || chainId == ChainId.MONAD || chainId == ChainId.MEGAETH
                || chainId == ChainId.ROBINHOOD || chainId == ChainId.ARC || chainId == ChainId.ETHERLINK
                || chainId == ChainId.TEMPO
        ) {
            return 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7;
        }
        return 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
    }
}

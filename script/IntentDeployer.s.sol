// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EphemeralFactory } from "../src/factory/EphemeralFactory.sol";
import { IntentEmitter } from "../src/helpers/IntentEmitter.sol";
import { ChainOwner } from "../src/libraries/ChainOwner.sol";
import { IntentRouter } from "../src/router/IntentRouter.sol";
import { KeeperWallet } from "../src/wallet/KeeperWallet.sol";
import { IntentDeployment } from "./IntentDeployment.sol";
import { KeeperWalletDeployment } from "./KeeperWalletDeployer.s.sol";

/// Deploys the intent stack on one chain: the ephemeral factory, the intent router, the intent
/// emitter and the keeper wallet. Every contract goes through the standard CREATE2 deployer (see
/// IntentDeployment), so the script can be re-run on a chain that is partly deployed. The keeper
/// wallet's address also commits to the deployer, its initial owner.
contract IntentDeployer is IntentDeployment, KeeperWalletDeployment {
    bytes32 internal constant EMITTER_SALT = "IntentEmitter";
    bytes32 internal constant WALLET_SALT = "KeeperWallet";

    function run()
        public
        returns (EphemeralFactory factory, IntentRouter router, IntentEmitter emitter, KeeperWallet wallet)
    {
        _requireSupported();

        bytes memory factoryCode = type(EphemeralFactory).creationCode;
        bytes memory routerCode = _routerCode();
        _requireLinked(factoryCode, EVALUATOR);
        _requireLinked(routerCode, EVALUATOR);
        _requireLinked(routerCode, HASH);

        factory = EphemeralFactory(_deploy(FACTORY_SALT, factoryCode));
        router = IntentRouter(payable(_deploy(ROUTER_SALT, routerCode)));
        emitter = IntentEmitter(_deploy(EMITTER_SALT, type(IntentEmitter).creationCode));
        wallet = _deployWallet(ChainOwner.ownerFor(block.chainid));
    }

    /// The deployer owns the wallet at first so it can authorize the executors, then hands it to the
    /// chain owner, who completes the two-step transfer with acceptOwnership(). A wallet already at
    /// the address is left as it is.
    function _deployWallet(address owner) private returns (KeeperWallet wallet) {
        // forge-lint: disable-next-line(unused-return)
        (, address deployer,) = vm.readCallers();
        bytes memory code = abi.encodePacked(type(KeeperWallet).creationCode, abi.encode(deployer));
        bool existed = _predicted(WALLET_SALT, code).code.length != 0;
        wallet = KeeperWallet(payable(_deploy(WALLET_SALT, code)));
        if (existed) {
            return wallet;
        }

        address[] memory executors = _executors();
        vm.startBroadcast();
        for (uint256 i = 0; i < executors.length; ++i) {
            // forge-lint: disable-next-line(calls-loop)
            wallet.setExecutor(executors[i], true);
        }
        wallet.transferOwnership(owner);
        vm.stopBroadcast();
    }
}

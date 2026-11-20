// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../src/intent/BridgeGuardian.sol";
import { BridgeConfig } from "./BridgeConfig.sol";

/// Salted CREATE2 with this chain's configuration from BridgeConfig. The address differs per chain;
/// each chain's leaf names its own guardian.
contract BridgeGuardianDeployer is BridgeConfig {
    function run() public returns (BridgeGuardian guardian) {
        _requireSupported();
        GuardianConfig memory config = _guardianConfig();
        require(config.tokenMessenger != address(0) || config.spokePool != address(0), "no bridge on this chain");
        _checkLocal(config);

        guardian = BridgeGuardian(_deploy(GUARDIAN_SALT, _guardianCreationCode(config)));
        require(address(guardian.tokenMessenger()) == config.tokenMessenger, "tokenMessenger mismatch");
        require(guardian.usdc() == config.usdc, "usdc mismatch");
        require(address(guardian.spokePool()) == config.spokePool, "spokePool mismatch");
        for (uint256 i; i < config.destinations.length; ++i) {
            BridgeGuardian.CctpDestination memory d = config.destinations[i];
            (uint32 domain, address usdc) = guardian.cctpDestinations(d.chainId);
            require(domain == d.domain && usdc == d.usdc, "destination mismatch");
        }
        for (uint256 i; i < config.routes.length; ++i) {
            BridgeGuardian.AcrossRoute memory r = config.routes[i];
            (uint128 mul, uint128 div) = guardian.acrossRoutes(keccak256(abi.encode(r.input, r.chainId, r.output)));
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 factor = 10 ** uint8(r.decimals < 0 ? -r.decimals : r.decimals);
            require(r.decimals < 0 ? mul == factor && div == 1 : mul == 1 && div == factor, "route mismatch");
        }
    }
}

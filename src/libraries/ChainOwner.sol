// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ChainId } from "./DataTypes.sol";

/// @notice Resolves the per-chain owner that deployer-owned contracts are migrated to.
/// @dev Chains without a configured owner revert, so a misconfigured chain can never be
///      migrated to the zero address (or a stale placeholder) silently.
library ChainOwner {
    address internal constant ENSO_OWNER = 0x4e3F2D3A840F602b132E1d4dc4709a13ef43Bf2c;
    address internal constant ZKSYNC_OWNER = 0x969Ae01a5eFdD9E2E2bc4EE2D179922b2A7e7aE6;
    address internal constant TODO_OWNER = 0xAf873a7Ab95090f2B01Fc38f492268c648C9E555;

    error UnconfiguredChain(uint256 chainId);

    function ownerFor(uint256 chainId) internal pure returns (address) {
        if (chainId == ChainId.ETHEREUM) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.OPTIMISM) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.BINANCE) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.GNOSIS) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.UNICHAIN) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.POLYGON) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.MONAD) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.SONIC) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.ZKSYNC) {
            return ZKSYNC_OWNER;
        }
        if (chainId == ChainId.WORLD) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.HYPER) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.SEI) {
            return TODO_OWNER; // TODO: replace with multisig once available
        }
        if (chainId == ChainId.SONEIUM) {
            return TODO_OWNER; // TODO: replace with multisig once available
        }
        if (chainId == ChainId.TEMPO) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.MEGAETH) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.BASE) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.PLASMA) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.ARBITRUM) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.ETHERLINK) {
            return TODO_OWNER; // TODO: replace with multisig once available
        }
        if (chainId == ChainId.AVALANCHE) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.INK) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.LINEA) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.BERACHAIN) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.PLUME) {
            return TODO_OWNER; // TODO: replace with multisig once available
        }
        if (chainId == ChainId.KATANA) {
            return ENSO_OWNER;
        }
        if (chainId == ChainId.ROBINHOOD) {
            return TODO_OWNER; // TODO: replace with multisig once available
        }
        revert UnconfiguredChain(chainId);
    }
}

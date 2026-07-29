---
name: add-new-chain
description: Add or review support for a new EVM chain in shortcuts-client-contracts, including chain IDs, ownership, deployment configuration, contract broadcasts, and verification. Use for an Enso chain rollout or a repository PR checklist.
---

# Add New Chain

Treat this repository as the source of deployed Enso contract evidence. Never fabricate
deployment addresses, verification results, ownership, or broadcast artifacts.

## Establish scope

1. Record the issue reference, chain name, decimal ID, canonical slug, explorer, verification API,
   and public chain documentation.
2. Determine which contracts and optional integrations are in scope from current repository
   interfaces and public provider documentation.
3. Mark flashloans, CCIP, and LayerZero separately as supported, not applicable, or unsupported.
4. Inspect existing chain implementations and current source before editing.

Start the GitHub PR body from [assets/pr-body.md](assets/pr-body.md), replace every placeholder,
and link public evidence for every deployment-specific value.

## Implement

- Add the numeric constant to `src/libraries/DataTypes.sol`.
- Add the intended owner to `src/libraries/ChainOwner.sol`; do not leave an accidental placeholder
  owner.
- Update `.bash/deploy.sh` for chain-specific explorer verification when required.
- Configure `script/EnsoCCIPReceiverDeployer.s.sol` only with verified CCIP support.
- Configure `script/LayerZeroDeployer.s.sol` only with verified LayerZero support.
- Configure `script/FlashloanAdapterConfig.s.sol` only with verified lender deployments.
- Audit all core deployment scripts for exhaustive chain branches.
- Commit broadcast records only after real broadcasts; never hand-author them to resemble a
  deployment.

## Prepare the PR

Include GitHub task-list items for:

- [ ] Chain ID and public chain documentation linked.
- [ ] Configured owner and contract addresses verified on-chain.
- [ ] Broadcast transaction links recorded for committed deployment artifacts.
- [ ] Optional adapter and bridge contracts verified or marked not applicable.
- [ ] Contracts verified on the explorer.

Do not include private service names, infrastructure configuration, credentials, internal
trackers, or non-public operational procedures.

## Validate

```bash
forge fmt --check
forge test
pnpm format
```

Also compare deployed bytecode, constructor inputs, and owners with the intended configuration.

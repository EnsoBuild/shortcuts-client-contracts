---
name: add-new-chain
description:
  Prepare or review human-gated support for a new EVM chain in
  shortcuts-client-contracts, including chain IDs, ownership inputs, deployment
  configuration, public integration research, tests, contract broadcasts, and
  verification evidence. Use for an Enso chain rollout or a repository PR
  checklist.
---

# Add New Chain

Treat this repository as the source of deployed Enso contract evidence. Never
fabricate deployment addresses, verification results, ownership, or broadcast
artifacts.

Treat the rollout as a human-agent workflow. The agent prepares research, code,
tests, commands, and evidence; an authorized human makes launch-scope and
custody decisions and performs privileged wallet actions.

## Respect human gates

The agent may:

- Inventory existing chain branches and propose candidate contracts or
  integrations.
- Collect candidate addresses from public provider documentation and verified
  explorer pages.
- Prepare configuration, tests, deployment commands, and an explicitly partial
  PR checklist.
- Run local tests and public-RPC simulations when the user supplies suitable
  access.

Require an authorized human to:

- Decide which protocols, lenders, and optional integrations are in launch
  scope.
- Create or select the owner wallet, including a Safe multisig or an approved
  hardware-wallet fallback, and provide the final owner address.
- Approve signers, thresholds, custody policy, RPC credentials, and explorer
  credentials.
- Sign or approve broadcasts, ownership transfers, and verification
  transactions.
- Confirm deployed state and complete the human-only PR checklist.

If the owner or protocol scope is missing, record the item as blocked and ask
for it. Do not create a wallet, choose signers, select protocols on the team's
behalf, or silently substitute an EOA.

## Establish scope

1. Record the issue reference, chain name, decimal ID, canonical slug, explorer,
   verification API, and public chain documentation.
2. Inventory candidate contracts and optional integrations from current
   repository interfaces and public provider documentation. Ask the human owner
   to approve the launch scope.
3. Mark flashloans, CCIP, and LayerZero separately as supported, not applicable,
   or unsupported.
4. Inspect existing chain implementations and current source before editing.

Start the GitHub PR body from [assets/pr-body.md](assets/pr-body.md), replace
every placeholder, and link public evidence for every deployment-specific value.

## Research optional integrations

- For flashloan lenders, find the protocol's official deployment documentation
  and corroborate the address, chain, contract role, and bytecode on the chain
  explorer. Report candidates and gaps; require human approval before adding a
  lender to launch scope.
- For CCIP, use the official
  [mainnet](https://docs.chain.link/ccip/directory/mainnet) or
  [testnet](https://docs.chain.link/ccip/directory/testnet) directory to verify
  chain support, Router, chain selector, TokenAdminRegistry, and required lanes
  or tokens. Treat the Enso receiver and its owner as separate Enso deployments.
- For LayerZero, use the official
  [deployed-contracts directory](https://docs.layerzero.network/v2/deployments/deployed-contracts)
  to verify the EndpointV2 address and EID. If Stargate is in scope, verify the
  required asset separately in the official
  [Stargate asset directory](https://docs.layerzero.network/v2/deployments/oft-ecosystem-stargate-assets).
  Endpoint availability alone does not prove Stargate asset or pathway
  availability.

For every candidate value, record the public source, chain ID, contract role,
checksum address, and observation date. A search result or an unverified
third-party list is not deployment evidence.

## Implement

- Add the numeric constant to `src/libraries/DataTypes.sol`.
- Add the intended owner to `src/libraries/ChainOwner.sol`; do not leave an
  accidental placeholder owner.
- Update `.bash/deploy.sh` for chain-specific explorer verification when
  required.
- Configure `script/EnsoCCIPReceiverDeployer.s.sol` only with verified CCIP
  support.
- Configure `script/LayerZeroDeployer.s.sol` only with verified LayerZero
  support.
- Configure `script/FlashloanAdapterConfig.s.sol` only with verified lender
  deployments.
- Audit all core deployment scripts for exhaustive chain branches.
- Commit broadcast records only after real broadcasts; never hand-author them to
  resemble a deployment.

## Prepare the PR

Keep agent-preparable and human-only items visibly separate. The agent may check
an item only when the linked evidence or command output proves it. Include
task-list items for:

- [ ] Chain ID and public chain documentation linked.
- [ ] Configured owner and contract addresses verified on-chain.
- [ ] Broadcast transaction links recorded for committed deployment artifacts.
- [ ] Optional adapter and bridge contracts verified or marked not applicable.
- [ ] Contracts verified on the explorer.

Leave wallet creation, owner approval, launch-scope approval, transaction
signing, and final on-chain attestation unchecked for the authorized human.

Do not include private service names, infrastructure configuration, credentials,
internal trackers, or non-public operational procedures.

## Validate

```bash
forge fmt --check
forge test
pnpm format
```

Also compare deployed bytecode, constructor inputs, and owners with the intended
configuration.

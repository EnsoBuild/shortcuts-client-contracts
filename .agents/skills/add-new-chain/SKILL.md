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

## Prepare the checkout

A fresh worktree has no `dependencies/` (soldeer), `lib/`, or `node_modules/`,
and `forge build` fails with "more than 256 errors". Before editing:

```bash
forge soldeer install   # or copy dependencies/ and lib/ from the main checkout
pnpm install
forge build
```

Check that every entry in `dependencies/` is populated; an empty directory left
by an aborted install hides the missing package from `forge soldeer install`.

## Establish scope

1. Record the issue reference, chain name, decimal ID, canonical slug, explorer,
   verification API, and public chain documentation. Cite only public sources in
   the PR; facts without a public source stay `TBD` in the PR and are
   re-verified when the chain's documentation publishes them.
2. Record the chain's EVM differences that touch this repository: gas token and
   its decimals, whether a wrapped-native contract exists, value-transfer rules
   (for example, sends to `address(0)` or blocklisted addresses reverting),
   `SELFDESTRUCT` semantics, fee floors, and finality. Stablecoin-gas chains
   (Tempo, Arc) have no wrapped native and a 6/18-decimal split; do not assume a
   WETH-style chain.
3. Verify the prerequisite contracts on-chain with `eth_getCode`: the Arachnid
   CREATE2 factory `0x4e59b44847b379578588920cA78FbF26c0B4956C` (deterministic
   addresses depend on it), Multicall3, and Permit2 when in scope.
4. Inventory candidate contracts and optional integrations from current
   repository interfaces and public provider documentation. Ask the human owner
   to approve the launch scope.
5. Mark flashloans, CCIP, and LayerZero separately as supported, not applicable,
   or unsupported.
6. Inspect existing chain implementations and current source before editing. The
   most recent chain-add commit is the best map of the touched files.

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
- For LayerZero, query the machine-readable
  [metadata API](https://metadata.layerzero-api.com/v1/metadata) first and match
  on `chainDetails.nativeChainId`; it returns the chain key, the v2 EID, and the
  EndpointV2 address. Cross-check on the official
  [deployed-contracts directory](https://docs.layerzero.network/v2/deployments/deployed-contracts).
  If Stargate is in scope, verify the required asset separately in the official
  [Stargate asset directory](https://docs.layerzero.network/v2/deployments/oft-ecosystem-stargate-assets).
  Endpoint availability alone does not prove Stargate asset or pathway
  availability.

  ```bash
  curl -s https://metadata.layerzero-api.com/v1/metadata | jq -r \
    'to_entries[] | select(.value.chainDetails.nativeChainId == <CHAIN_ID>)
     | "\(.key) eid=\(.value.deployments[] | select(.version == 2) | .eid) endpointV2=\(.value.deployments[] | select(.version == 2) | .endpointV2.address)"'
  ```

For every candidate value, record the public source, chain ID, contract role,
checksum address, and observation date. A search result or an unverified
third-party list is not deployment evidence.

Never conclude that a provider does **not** support the chain from a summarised
or truncated read of a large directory page. A negative needs either a
machine-readable source (API, JSON, on-chain code check) or a human who opened
the directory page and confirmed the absence. Until one exists, mark the
integration `unverified`, not `not applicable`, and hand the link to the human.

## Implement

Ordering conventions: `DataTypes.sol` and `ChainOwner.sol` by chain ID;
`.env.example`, `foundry.toml` `[rpc_endpoints]`, and the CI secret list
alphabetically (`ARBITRUM` before `ARC` before `AVALANCHE`).

- Add the numeric constant to `src/libraries/DataTypes.sol`.
- Add the intended owner to `src/libraries/ChainOwner.sol`. When the multisig
  does not exist yet, use the repository's `TODO_OWNER` with a
  `// TODO(<ticket>)` comment and list the owner as a blocked human decision in
  the PR; never invent an address.
- Add `<CHAIN>_RPC_URL=` and `<CHAIN>_BLOCKSCAN_KEY=` to `.env.example`, the
  `<chain> = "${<CHAIN>_RPC_URL}"` alias to `foundry.toml` `[rpc_endpoints]`,
  and the `<CHAIN>_RPC_URL` secret to `.github/workflows/ci.yml`.
- Update `.bash/deploy.sh` for chain-specific explorer verification. Supported
  verifier kinds are `etherscan`, `blockscout`, `routescan`, and `tempo`. When
  the explorer or its API is unconfirmed, add the branch with a `TODO(<ticket>)`
  and leave the PR item unchecked.
- Configure `script/EnsoCCIPReceiverDeployer.s.sol` only with verified CCIP
  support. For a chain without CCIP, add the branch with
  `ccipRouter = address(0)`; the script's `CCIPRouterIsNotSet` check makes a
  premature deploy revert.
- Configure `script/LayerZeroDeployer.s.sol` only with verified LayerZero
  support. Its final `else` deploys with Ethereum's endpoint for any unknown
  chain, so add an explicit `revert UnsupportedChainId(chainId)` branch for a
  chain without LayerZero.
- Configure `script/FlashloanAdapterConfig.s.sol` only with verified lender
  deployments.
- Audit all core deployment scripts for exhaustive chain branches
  (`grep -rn "block.chainid\|ChainId\." script`).
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

## Publish only public information

PR bodies, commit messages, code comments, and review comments are public. Never
include:

- RPC endpoints, provider names, API keys, or how access was obtained;
- documentation that is not public, its URL, or facts that exist only there;
- addresses, chain parameters, or launch details the chain or protocol has not
  published yet;
- credentials, internal trackers, infrastructure configuration, or non-public
  operational procedures.

When a value is needed but has no public source, write `TBD` and keep the
private detail in the team's internal tracker. Re-scan the PR body and the diff
for these terms before opening the PR.

## Validate

```bash
forge fmt --check
forge build
forge test --no-match-test "invariant_.*" --no-match-path "test/fork/**"
pnpm format
```

Fork tests need the chain's RPC in `.env` and run in CI once the secret exists.

Pre-compute the expected deterministic addresses and compare them with the
existing address families before any broadcast; a mismatch means bytecode or
compiler drift:

```bash
cast create2 --deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --salt "$(cast format-bytes32-string EnsoRouter)" \
  --init-code "$(forge inspect src/router/EnsoRouter.sol:EnsoRouter bytecode)"
```

Dry-run a deployer against the chain without signing by calling
`.bash/deploy.sh <Script>.s.sol <chain>` without the `broadcast` argument. When
invoking `forge script` directly, pass `--tc <ContractName>`; several deployer
files declare a contract named `Deployer`, not the file name.

After broadcasting, compare deployed bytecode, constructor inputs, and owners
with the intended configuration.

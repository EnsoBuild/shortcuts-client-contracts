## Add {{CHAIN_NAME}} (`{{CHAIN_ID}}`) contract support

Issue: `{{TICKET}}` · Downstream integration: tracked internally

### What this PR changes

| File                                                       | Change                                           |
| ---------------------------------------------------------- | ------------------------------------------------ |
| `src/libraries/DataTypes.sol`                              | `ChainId.<NAME> = {{CHAIN_ID}}`                  |
| `src/libraries/ChainOwner.sol`                             | owner, or `TODO_OWNER` with `TODO({{TICKET}})`   |
| `script/EnsoCCIPReceiverDeployer.s.sol`                    | TBD, or zero router when CCIP is not live        |
| `script/LayerZeroDeployer.s.sol`                           | TBD, or explicit revert when LayerZero is absent |
| `script/FlashloanAdapterConfig.s.sol`                      | TBD, or not in scope                             |
| `.bash/deploy.sh`                                          | verifier branch, or TODO when unconfirmed        |
| `foundry.toml`, `.github/workflows/ci.yml`, `.env.example` | rpc alias, CI secret, env vars                   |

### Integration status

| Integration       | Status | Basis |
| ----------------- | ------ | ----- |
| Core contracts    | TBD    |       |
| CCTP              | TBD    |       |
| LayerZero         | TBD    |       |
| CCIP              | TBD    |       |
| Flashloan adapter | TBD    |       |

One artifact per checkbox. A box is checked only when that single artifact is
done and its evidence is in this PR.

### Repository changes, one artifact per box

- [ ] `DataTypes.sol`: `ChainId.<NAME> = {{CHAIN_ID}}`, ordered by chain id.
- [ ] `ChainOwner.sol`: owner, or `TODO_OWNER` with `TODO({{TICKET}})`.
- [ ] `.env.example`: `<CHAIN>_RPC_URL`, `<CHAIN>_BLOCKSCAN_KEY` (alphabetical).
- [ ] `foundry.toml`: `<chain>` in `[rpc_endpoints]` (alphabetical).
- [ ] `ci.yml`: `<CHAIN>_RPC_URL` secret (alphabetical).
- [ ] `.bash/deploy.sh`: verifier branch, or TODO with the reason.
- [ ] `EnsoCCIPReceiverDeployer.s.sol`: branch, with the Router or a guarded
      zero.
- [ ] `LayerZeroDeployer.s.sol`: endpoint group, or explicit revert.
- [ ] `FlashloanAdapterConfig.s.sol`: one box per lender: `<lender>`.
- [ ] Focused tests, or "no test surface" with the reason.

### Pre-deploy verification, one artifact per box

- [ ] CREATE2 factory `0x4e59…56C` has code on the target network.
- [ ] Multicall3 has code on the target network.
- [ ] Permit2 has code on the target network (when in scope).
- [ ] Native/gas asset facts checked on-chain (decimals, wrapper presence).
- [ ] Expected `EnsoRouter` address via `cast create2`, and the family it
      matches.
- [ ] Expected helper addresses via `cast create2`.
- [ ] Expected receiver addresses via `cast create2` (owner-dependent; note the
      owner used).
- [ ] Lender bytecode checked on the target network (one box per lender).
- [ ] `FullDeployer` dry run against the target RPC.

### Human decisions, one per box

- [ ] Launch contract scope approved (list the contracts).
- [ ] Owner: Safe multisig created/selected, or hardware-wallet fallback
      approved. Address: TBD
- [ ] Signer/threshold and custody configuration approved.
- [ ] Deployer funded for gas.
- [ ] RPC configured in `.env` and as a CI secret.
- [ ] Explorer access and verification method decided.

### Deployment and evidence, one artifact per box

- [ ] `FullDeployer` broadcast; transaction links: TBD
- [ ] `EnsoRouter` address confirmed equal to the expected one.
- [ ] Helper addresses confirmed equal to the expected ones.
- [ ] `EnsoCCIPReceiver` broadcast; address: TBD (or not in scope)
- [ ] `LayerZeroReceiver` broadcast; address: TBD (or not in scope)
- [ ] Flashloan adapters broadcast; addresses: TBD (or not in scope)
- [ ] Broadcast artifacts committed under `broadcast/<script>/{{CHAIN_ID}}/`,
      produced by the real runs.
- [ ] Contracts verified on the explorer; links: TBD
- [ ] Owner and deployed state confirmed on-chain.

### Public evidence

_Chain documentation, provider directory entries and machine-readable sources,
with dates. Cite only public sources; write TBD where none exists yet._

### Chain-specific EVM differences

_Gas token and decimals, wrapped-native availability, value-transfer rules, fee
floor, finality, simulation caveats. Write "none beyond standard EVM" when that
is verified._

### Validation

- [ ] `forge fmt --check`
- [ ] `forge build`
- [ ] `forge test --no-match-test "invariant_.*" --no-match-path "test/fork/**"`
- [ ] `pnpm format`
- [ ] Deployed bytecode, constructor inputs and owner checked on-chain.

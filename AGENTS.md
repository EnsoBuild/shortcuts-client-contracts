# AGENTS.md — shortcuts-client-contracts

Solidity execution surfaces for Enso Shortcuts: routers, wallets, account
abstraction, bridge receivers, solvers, flashloans, and helpers.

## Knowledge catalogue

Purpose: bootstrap agent context so work is holistic, secure, and high-quality —
without rediscovering the same logic streams, quirks, and gotchas every session.

- Start at root [`KNOWLEDGE.md`](./KNOWLEDGE.md); read the stream file for the
  area you touch **before** changing it.
- Follow cross-links into scripts, consumers, and sibling repositories whenever
  a change crosses an ABI, address, payload, or trust boundary.
- Treat catalogue facts as a head start, not gospel: **verify in code** and
  investigate when the task needs depth, something looks stale, or the change is
  security/money/on-chain sensitive.
- Distinguish current source, historical broadcast artifacts, off-chain address
  registries, and live chain state. None substitutes for the others.
- When you learn something durable and high-leverage (invariants, failure/leak
  surfaces, non-obvious contracts, deployment or cross-repo coupling), **update
  the relevant `KNOWLEDGE.md` in the same PR**. Replace stale facts instead of
  appending history.
- Keep entries **concise** — core flow, trust boundaries, invariants/gotchas,
  key flags/files. Exclude volatile address snapshots, temporary rollout state,
  one-off bugs, and line-level detail unless correctness depends on it.
- `<!-- verified-against: ... -->` records the commit whose code was checked.
  Change it only after re-validating the whole file; a newer code commit is a
  prompt to verify affected claims, not to update the hash mechanically.

## Related repositories

| Repo                                   | Role                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------- |
| **shortcuts-client-contracts** (this)  | On-chain execution and settlement surfaces                                |
| **shortcuts-builder**                  | Encodes these ABIs, payloads, CREATE2 formulas, and deployment addresses  |
| **shortcuts-backend-dynamic**          | Builds and submits router, wallet, bridge, paymaster, and flashloan flows |
| **shortcuts-standards**                | Emits protocol calls and consumes helper/flashloan interfaces             |
| **rust-quoter**                        | Simulates contract payloads and state overrides                           |
| **enso-weiroll** / **enso-weiroll.js** | On-chain VM and off-chain planner                                         |

## Quick pointers

- Shared Weiroll and multisend semantics:
  [`src/KNOWLEDGE.md`](./src/KNOWLEDGE.md)
- Router/shared wallet: [`src/router/KNOWLEDGE.md`](./src/router/KNOWLEDGE.md)
- Wallets, delegates, factories, ERC-4337, paymaster:
  [`src/wallet/KNOWLEDGE.md`](./src/wallet/KNOWLEDGE.md)
- Bridge receivers: [`src/bridge/KNOWLEDGE.md`](./src/bridge/KNOWLEDGE.md)
- Solvers: [`src/solvers/KNOWLEDGE.md`](./src/solvers/KNOWLEDGE.md)
- Flashloan adapters:
  [`src/flashloan/KNOWLEDGE.md`](./src/flashloan/KNOWLEDGE.md)
- Helpers: [`src/helpers/KNOWLEDGE.md`](./src/helpers/KNOWLEDGE.md)
- Deployments and live verification:
  [`script/KNOWLEDGE.md`](./script/KNOWLEDGE.md)

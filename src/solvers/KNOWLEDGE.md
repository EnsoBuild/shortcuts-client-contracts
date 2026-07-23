<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Solver execution

Core files: `BaseSolver.sol`, `BebopSolver.sol`, `MinimalWallet.sol`, and solver
deployers.

## Authority and custody

- `BaseSolver` accepts Weiroll programs only from immutable `executor`. That
  executor has arbitrary program authority over solver-held assets.
- Immutable `owner` can recover native/ERC-20/ERC-721/ERC-1155 and revoke
  approvals, always back to itself, but has no general arbitrary-call rescue
  surface.
- `BebopSolver` additionally requires `tx.origin == relayer`. Both the immediate
  executor and origin EOA conditions must hold; this deliberately excludes smart
  relayers/account-abstraction and makes origin part of the trust model.
- Constructors reject zero owner/executor/relayer. Roles cannot rotate, so
  changing authority requires redeployment/address migration.
- Solvers are settlement wallets, not passive custody. Minimize residual
  funds/approvals and verify the external settlement system's atomicity.

## Source/live ABI divergence

Current source and active integration are different generations:

- Current source:
  `executeShortcut(bytes32 accountId, bytes32 requestId, bytes32[], bytes[])`,
  selector `0x95352c9f`.
- Builder's Bebop client: legacy
  `executeShortcut(bytes32 requestId, bytes32[], bytes[])`, selector
  `0x8fd8d1bb`, against its registered Arbitrum address.
- Live bytecode at the builder address and the repository's recorded Arbitrum
  deployment exposes the legacy selector, not the current selector/current
  immutable getters.

A new deployment built from current source is not a drop-in replacement.
Coordinate Solidity deployment, builder ABI/address, backend calls, tests, and
rollout; compare live runtime with the historical source commit rather than
assuming present HEAD.

## Recovery gotchas and tests

- `MinimalWallet` recovery dispatches by asset protocol. Preserve strict
  validation when adding asset types; invalid enum values must not become silent
  no-ops.
- Approval revocation is owner-controlled and should be part of settlement
  incident response.
- This repository has no solver test suite. Add authorization, origin behavior,
  withdrawal/revocation, ABI compatibility, retained assets, and program-failure
  cases before modifying or redeploying this stream.

<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# shortcuts-client-contracts — knowledge catalogue

Bootstrap map for agents working on Enso's Solidity execution layer. Read the
relevant stream file first, then verify the claims that matter to the task in
current code, consumers, deployment history, and live state.

This repository executes Weiroll programs through several custody and
authorization models: a public router with a shared wallet, owned or delegated
wallets, ERC-4337 accounts, bridge callbacks, solver settlement, and flashloan
adapters. Many contracts deliberately accept arbitrary call programs; their
safety comes from the caller boundary, wallet context, atomicity, and strict
balance/approval cleanup rather than from allowlisting every downstream call.

## Streams

- [`src/KNOWLEDGE.md`](src/KNOWLEDGE.md) — common Weiroll VM, multisend, asset,
  and identity semantics.
- [`src/router/KNOWLEDGE.md`](src/router/KNOWLEDGE.md) — public router, shared
  `EnsoShortcuts`, safe-output checks, and dust/approval hazards.
- [`src/wallet/KNOWLEDGE.md`](src/wallet/KNOWLEDGE.md) — Wallet V2,
  Receiver/ERC-4337, factories, delegates, EIP-7702, and signature paymaster.
- [`src/bridge/KNOWLEDGE.md`](src/bridge/KNOWLEDGE.md) — LayerZero and CCIP
  authentication, replay/recovery, refunds, and payloads.
- [`src/solvers/KNOWLEDGE.md`](src/solvers/KNOWLEDGE.md) — solver custody,
  authorization, settlement, and deployed-ABI drift.
- [`src/flashloan/KNOWLEDGE.md`](src/flashloan/KNOWLEDGE.md) — lender callbacks,
  adapter-specific authority, repayment, and wallet integration.
- [`src/helpers/KNOWLEDGE.md`](src/helpers/KNOWLEDGE.md) — pure/view helpers and
  permissionless asset-moving helpers.
- [`script/KNOWLEDGE.md`](script/KNOWLEDGE.md) — CREATE2, ownership, broadcasts,
  live verification, CI, and operational hazards.

## System-wide invariants

- `commands` and `state` are executable input, not declarative metadata. Audit
  the actual wallet context, callable surface, value path, and approval
  lifecycle.
- `accountId` and `requestId` are event correlation fields. They do not
  authorize, isolate balances, or prevent replay.
- Native asset descriptors generally select a value path; their encoded `amount`
  is not consistently authoritative. Read each entry point's `msg.value` rules.
- Public/shared execution contracts must not retain user funds or useful
  approvals. A later caller can often choose arbitrary downstream calls and
  benefit from residue.
- Receiver/min-output checks prove only the measured postcondition. They do not
  make arbitrary calls safe or guarantee every intermediate asset was consumed.
- Address correctness is cross-repository.
  `shortcuts-builder/src/client/addresses.ts` and its ABIs/factory formulas are
  production consumers; backend and standards compose those values. An on-chain
  ABI or deployment change is incomplete until consumers are reconciled.
- Never infer a deployed contract from a salt or `run-latest.json` alone.
  CREATE2 depends on deployer and init code (including constructor arguments),
  broadcasts can be incomplete, source can move ahead of deployed bytecode, and
  two-step ownership acceptance may happen elsewhere.

## High-risk review checklist

When changing an execution surface:

1. Identify who can enter it and whose storage/assets are used (`CALL`,
   self-call, clone call, or `DELEGATECALL`).
2. Trace native value, token pulls, approvals, refunds, dust, callbacks, and the
   revert boundary.
3. Check replay/nonce responsibility and whether identifiers are merely logged.
4. Reconcile Solidity ABI/payload/address changes with builder, backend,
   standards, and live deployments.
5. Exercise failure paths, malformed input, zero roles, reentrancy, and
   retained-balance cases — not only successful routing.
6. For deployment work, follow [`script/KNOWLEDGE.md`](script/KNOWLEDGE.md) and
   verify live code plus current roles/immutables after broadcast.

## Tooling and tests

- Solidity `0.8.28`, optimizer + `via_ir`, Cancun EVM, metadata disabled;
  dependencies are pinned through Soldeer.
- CI installs current stable Foundry, runs formatting/lint/build, then the suite
  excluding tests named `invariant_.*`. The repository currently has no
  effective invariant-test layer; do not assume the exclusion represents
  invariant coverage.
- Fork suites require configured RPC secrets and may use pinned historical
  blocks. A passing fresh-contract fork test is not proof that a recorded
  production address runs current source.
- Mutation tooling temporarily swaps files under `src/`; after interruption,
  verify originals were restored and generated directories are not staged.
- `foundry.toml` labels many files “already audited” only inside format/lint
  ignore lists. It is not a security or deployed-version assertion.

## Cross-repo map

- **shortcuts-builder** owns client-side ABI encoding, wallet selection, bridge
  callback layouts, deterministic address calculations, and the principal
  address registry.
- **shortcuts-backend-dynamic** selects execution clients, assembles
  checkout/paymaster and bridge operations, and configures certain on-chain
  roles such as LayerZero OFTs.
- **shortcuts-standards** emits calls that target helpers/adapters and must
  agree on their ABI and wallet assumptions.
- **enso-weiroll** defines the on-chain VM; **enso-weiroll.js** plans its
  command/state encoding.
- **rust-quoter** simulates produced transactions; simulation assumptions must
  match the same deployed code and state being quoted.

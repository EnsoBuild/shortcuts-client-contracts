<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Deployment, ownership, and on-chain verification

Core files: `*Deployer.s.sol`, `FullDeployer.s.sol`, `RoleMigration.s.sol`,
`FlashloanAdapterConfig.s.sol`, `src/libraries/ChainOwner.sol`,
`.bash/deploy.sh`, `.bash/migrate-roles.sh`, and `broadcast/`.

## Deployment model

- Deployers use named CREATE2 salts, but salt is only one input. Address also
  depends on deploying address and init code, including constructor arguments,
  compiler/code, and deployment mechanism. zkSync uses a distinct system path.
- `FullDeployer` deploys router, delegate, Wallet V2 implementation/factory, and
  core helpers. Router creates its `EnsoShortcuts` child internally with
  ordinary `CREATE`.
- Constructor-less artifacts can share addresses across chains only while
  deployer, bytecode, and deployment path match. Chain-specific immutables
  commonly produce different bridge/flashloan addresses.
- `ChainOwner.ownerFor` fails closed for unconfigured chains, but several
  configured chains intentionally map to a temporary owner. Read the library
  rather than copying a volatile chain/address table into documentation.
- Bridge deployers have their own router/endpoint groupings. LayerZero has
  defaults for otherwise owner-configured chains; CCIP enumerates support.
  Adding a chain to `ChainOwner` is not enough to prove correct protocol/router
  selection.
- Receiver implementation deployment is two transactions: CREATE2 then
  `initialize(0,0,0)` to brick it. Clone initialization is atomic, but the
  implementation step has a front-run window.
- Paymaster and CCIP use `Ownable2Step`; a deploy/migration transaction may only
  set `pendingOwner`. Acceptance is a separate live-state requirement.

## Source, artifact, registry, live state

Keep four evidence layers separate:

1. **Current source** — what a new build/deployment would produce.
2. **Broadcast artifact** — historical intent/transactions tied to its recorded
   `.commit`; it may lack successful receipts or reflect older source.
3. **Consumer registry** — especially
   `shortcuts-builder/src/client/addresses.ts` and hard-coded ABI/selectors.
4. **Live chain** — runtime bytecode, immutable config, owner/pending owner,
   registrars/signers/lenders, balances, and code at dependent addresses.

Never “refresh” an address from current source plus an old salt. Historical
bridge deployments used different constructor ownership from current scripts, so
rerunning can create a parallel address. Current solver source also differs from
a legacy solver ABI still used by builder/live deployments.

## Verification workflow

1. Inspect `broadcast/<script>/<chain>/run-latest.json`: transaction/receipt
   counts, every receipt status, pending entries, returns, and `.commit`.
2. Read the deployer at that historical commit, including constructor args,
   chain routing, CREATE2 deployer, and post-deploy calls.
3. Query live `eth_getCode`; compare runtime against the historical build when
   source has moved.
4. Query immutables and roles. At minimum:
   - router: `shortcuts()` and code at the child;
   - wallet/Receiver factories: implementation and EntryPoint;
   - LZ: endpoint/router/owner/registrars/OFT mappings;
   - CCIP: protocol router/Enso router/owner/pending owner/pause/version;
   - paymaster: EntryPoint/owner/pending owner/signers/deposit/stake;
   - flashloan: owner and lender/callback configuration.
5. Verify two-step ownership acceptance independently and reconcile the
   address/ABI in builder plus backend/standards consumers.
6. Treat explorer verification as source publication, not proof of runtime
   configuration or current control.

## Role migration and keys

- `RoleMigration` reads addresses from latest broadcasts unless limited
  environment overrides exist. It changes registrar/signer roles before
  ownership and acts only under specific current-owner assumptions.
- LayerZero/flashloan ownership transfers are immediate; paymaster/CCIP
  transfers nominate pending owners. The script later distributes deployer funds
  and is not safely characterized as ownership-only.
- Migration rerun suppression depends on LayerZero state, so partial estates
  require direct live inspection.
- Normal deployment wrapper uses an encrypted Foundry keystore. Role migration
  and the Smardex deployer are exceptions that read raw `PRIVATE_KEY` from the
  environment; treat those as sensitive operational paths.

## Toolchain and operational checks

- Use pinned Soldeer revisions and a Foundry version compatible with this repo's
  remappings/config. CI intentionally installs current stable Foundry.
- Metadata/CBOR are disabled to stabilize bytecode, but source, constructor
  args, compiler behavior, and deployer still affect CREATE2.
- Some `run-latest` artifacts contain transactions/returns without receipts or
  pending transactions; file presence is never success proof.
- Run formatting, lint, `forge build --sizes`, focused tests, then the wider
  suite when RPCs permit. Fork test block/source context must match the claim
  being verified.
- After changing an ABI, deterministic formula, chain grouping, constructor,
  salt, owner, or role: update scripts/tests and the builder address/ABI
  registry in the same change set, then verify live postconditions after
  deployment.

<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Flashloan adapters

Core files: `AbstractEnsoFlashloan.sol`, three concrete adapters,
`IEnsoFlashloan.sol`, `script/FlashloanAdapterConfig.s.sol`, and
`test/flashloan/`.

## Common protocol flow

- ABI-stable protocol enum values are Morpho `1`, Aave V3 `2`, Balancer V3 `3`,
  Dolomite `4`, Uniswap V3 `5`. Keep them synchronized with
  `shortcuts-standards/src/helpers/flashloan.ts`.
- Public `executeFlashloan` decodes lender-specific data, opens a transient
  context, invokes the lender, authenticates the callback/context, executes the
  supplied Weiroll program in the adapter-specific wallet, verifies repayment
  while preserving the adapter's pre-loan balance, repays, and clears context.
- Morpho/Balancer authenticate callback sender. Aave also checks
  `initiator == adapter`; Dolomite checks callback `sender == adapter`; Uniswap
  derives the expected pool from trusted factory/token pair/fee.
- Active context blocks replay and same-context recursion. Nested loans with a
  different protocol/lender/token tuple are intentionally allowed.
- Aave/Uniswap repayment includes fees; the other supported integrations use
  their protocol's zero-fee principal repayment path.

## Adapter authority

- **Wallet adapter:** principal goes to initiating `msg.sender`; that EnsoWallet
  must authorize the adapter as executor so the callback can run Weiroll.
- **Safe adapter:** initiating Safe must enable the adapter as a module;
  callback delegatecalls `DelegateEnsoShortcuts` in Safe context.
- **Router adapter:** anyone may initiate; adapter approves the public router,
  which moves principal into its shared shortcuts wallet. Fees must be
  produced/supplied atomically without pre-funding that publicly sweepable
  wallet.
- Adapters have no rescue function and must not retain funds. `trustedLenders`
  is constructor-seeded/removable only; new lenders cannot be added.
- Owner can pause/unpause entry and permanently remove lenders. Ownership, pause
  state, and lender configuration are operational security state, not source
  constants.

## Critical gotchas

- Trusted-lender verification occurs in callbacks, not before every initial
  lender call. A caller-supplied untrusted target can return without invoking
  the callback.
- Dolomite is the sharpest case: the adapter approves the caller-supplied margin
  address before `operate`. A fake margin can take tokens already held by the
  adapter and return without callback authentication. Treat zero retained
  balance as a hard invariant; changing this path deserves explicit pre-call
  trust validation.
- Duplicate token arrays break per-entry pre-balance preservation assumptions.
  Solidity does not centrally enforce token/amount length equality or
  uniqueness; standards currently does, but contract safety must not rely
  silently on an off-chain caller.
- Native/shared-wallet prefunding is not a fee mechanism: residue on public
  execution wallets can be stolen by later calls.

## Testing and change checklist

- Fork tests exercise all five protocols at a pinned Ethereum block, all three
  adapter modes, callback context checks, same-context recursion, and
  Wallet/Safe authorization.
- Material gaps: malformed lengths, duplicate tokens, untrusted targets that
  skip callbacks, the Dolomite pre-callback approval path, and retained-balance
  recovery.
- Any enum, callback ABI, lender, or adapter-address change must update
  standards, builder address getters, backend selection/executor grants,
  deployment config, and fork fixtures.
- Verify trusted-lender configuration, ownership, and pause state live;
  broadcast data is not authoritative. See
  [`script/KNOWLEDGE.md`](../../script/KNOWLEDGE.md).

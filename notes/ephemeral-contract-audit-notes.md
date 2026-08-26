# Ephemeral Intent Contracts — Auditor Notes

Prepared for the external (Dedaub) engagement. State as of commit `b41ec65`.
Scope: `src/factory/EphemeralFactory.sol`,
`src/wallet/EphemeralIntentExecutor.sol`, `script/EphemeralDeployer.s.sol`,
`src/helpers/IntentEmitter.sol`.

Two internal review rounds preceded this engagement. Every finding from both
rounds is either fixed in the current tree, refuted with evidence, or recorded
below as an explicit, signed-off policy decision. Please read the severity model
first — findings rated without it will be mis-rated.

---

## 1. The severity model: revert placement, not gas or complexity

The entire executor lifecycle runs in a constructor. The address is
`CREATE2(factory, salt = bytes32(0), keccak256(creationCode ++ abi.encode(intent)))`,
so an address can only ever host this one initcode. There is no admin, pause, or
upgrade path anywhere in the system. Severity of any revert is decided by where
it sits:

**PERMANENT BRICK** — a revert reachable from `_refund`, or in the constructor
before branch selection. No branch of the constructor completes, `selfdestruct`
never runs, no code is deposited, and the address can never be deployed to
again. Funds at the address are unrecoverable, permanently.

**LIVENESS ONLY** — a revert confined to the execute branch. Funds stay at the
address and the refund branch collects them once the deadline passes. Cheap by
construction; this is what lets the keeper retry aggressively.

### Zone map (line numbers @ `b41ec65`, `EphemeralIntentExecutor.sol`)

BRICK ZONE (must never revert):

- constructor prologue and branch selection: `:50-67` (context read, beneficiary
  substitution, chainid/deadline branching)
- `selfdestruct` at `:81` (outside the if/else — runs on every branch)
- `_refund` `:150`, `_payFee` with `strict=false` `:201`
- the tolerant family: `_tryAmount` `:288`, `_tryBalance` `:326`,
  `_tryTransfer(Token,…)` `:356`, `_tryTransfer(address,…)` `:383`,
  `_sweep(Token,…)` `:395`, `_sweep(address,…)` `:426`, `_word` `:441`

LIVENESS ZONE (reverts are acceptable and sometimes intended):

- execute arm `:68-77`, `_run` `:84`, `_constrained` `:93`, `_route` `:135`,
  `_liveToken` `:167`, `_requireTriggers` `:183`, `_approveTriggers` `:195`,
  `_payFee` with `strict=true`, `_approve` `:223`, `_value` `:249`, `_minOut`
  `:261`, `_amount` `:270`, `_balance` `:303`

Rules that follow from the model (also the maintainer edit rules):

- No validation, `require`, or shape check may be added to the constructor
  prologue or anywhere in the brick zone. On-chain shape validation is
  tolerant-skip only; strict validation belongs off-chain (SDK) or in a view
  where a revert costs nothing.
- In the tolerant family, length gates are `return`/`false`, never `require`;
  address words are truncated (`address(uint160(word))`), never validated; token
  calls are low-level with tolerant returndata handling.
- Only validator-bearing `abi.decode`s matter
  (address/contract/bool/enum-typed). `abi.decode(ret, (uint256))` preceded by a
  `ret.length >= 32` check cannot revert — do not churn those.
- `_requireTriggers` uses the tolerant `_tryBalance` on the balance side but the
  strict `_amount` on the amount side. This is deliberate: the delivery gate
  stays intact (malformed data still reverts, on the liveness branch), while
  ERC721 gets presence-of-the-committed-tokenId semantics. Do not make the
  amount side tolerant — `_tryAmount` returning 0 would delete the Underfunded
  check.
- `_payFee` serves both zones via the `strict` flag: typed reads + `SendFailed`
  on the execute branch, fully tolerant reads (skip the fee on any abnormality)
  on refund branches. The fee is paid FIRST on both (before sweeps / before the
  route).

The executable form of this section is
`test/unit/fuzz/wallet/ephemeralIntentExecutor/refundNeverReverts.t.sol` — four
fuzz properties at 1000 runs (committed trigger bytes, committed fee bytes,
wrong-chain branch, keeper sweep list), each asserting `executeIntent` completes
and the lifecycle terminates. On the pre-fix tree these found counterexamples in
≤ 4 runs. Recommended as a required CI check.

---

## 2. v1 production scope (signed off)

- CONSTRAINED mode. ROUTE mode exists and is tested but is not the v1 product
  path.
- Triggers and outcomes: ERC20 primary; **ERC721 and ERC1155 are in scope as
  production paths** (this supersedes the internal audit's ERC20-only scoping —
  the NFT arms were subsequently fixed and must be reviewed as first-class).
- No native deliveries are expected in v1 (relevant to the zero-recipient
  analysis: the native burn was moot even before the beneficiary substitution
  fix).
- Chains: Ethereum and Optimism.
- Keeper model: a single trusted keeper. **SDK policy sets
  `exclusiveUntil == deadline`**, making the exclusivity window and the
  executable window the same window: no third party can ever reach `_route`; an
  outsider reverts `Exclusive()` at the last executable second and the user gets
  a full refund one second later. This is policy, not contract law — the
  contract deliberately retains permissionless-fallback capability for later
  versions. Do not file the absence of an on-chain `exclusiveUntil >= deadline`
  check as a finding; it is a recorded decision.

### ERC721 second-word convention (direction-dependent, inherited from EnsoRouter)

The `Token.data` second word for ERC721 means different things by direction,
exactly as EnsoRouter's own `_transfer` (in) and `_checkMinAmountOut` (out) read
it:

- **In-side** (triggers, fee): a **tokenId**. Delivery = presence of that exact
  token (`_tryBalance` probes `ownerOf(id) == executor`, nonexistent ids map to
  0); `_amount` returns 1; the router pulls, and the refund sweep returns, that
  id.
- **Out-side** (`tokensOut`): a **minimum count** (`_minOut`), checked against
  the `balanceOf` delta at the recipient — because the id of a freshly minted
  position (e.g. a Uniswap V3 LP NFT) cannot be known at commit time.

The SDK's golden-vector tests must encode this (a trigger with a count, or an
outcome with an id, is a malformed intent).

---

## 3. Security decisions on record

**B4 — keeper surplus (decided): the keeper is trusted; the on-chain check is a
floor.** `_liveToken` re-amounts trigger tokens to live balances and the router
pulls them in full into the shared `EnsoShortcuts` contract before the shortcut
runs; the only post-condition is that recipient deltas clear absolute committed
minimums. Surplus a route does not consume sits in `EnsoShortcuts`, which is
first-come-first- served for any caller (pre-existing property of routing
through EnsoRouter for every integration, not specific to this system). The
recorded mitigation is a **written keeper requirement, not a contract change**:
keeper-built route bytes MUST size consumption dynamically from
`balanceOf(shortcuts)` (or equivalent balance-relative weiroll steps) rather
than embedding statically quoted amounts. A keeper following this requirement
leaks exactly zero, including on over-delivery and on the quote/inclusion race
(the residual exposure, which the keeper can also reclaim atomically).
Proportional on-chain minimums were considered and declined for v1;
`min(live, committed)` was evaluated and rejected (it deletes `_liveToken`'s
purpose and is near-vacuous given `_requireTriggers`). If the trust model
changes, this is the finding to reopen.

**Beneficiary substitution, not validation** (`:56-60`): `refundRecipient == 0`
substitutes the keeper everywhere (sweeps and selfdestruct). A prologue
`revert BadIntent()` was explicitly rejected — it would brick the execute branch
too, converting a conditional loss into an unconditional one.

**The blob is the address.** Funding the derived address is the only
authorization; `abi.encode(intent)` is inside the CREATE2 preimage. A hostile or
buggy author can only brick their own deposit — a different blob is a different
address no victim ever funds. The realistic threat behind the whole
malformed-intent class is an SDK/backend encoding defect amplified into
user-fund loss, not an exploit; this is why permanent- loss findings in that
class rate HIGH rather than CRITICAL. Corollary: a malformed entry in the
caller-supplied `sweep[]` reverts only the caller's own transaction and censors
nobody — not a DoS.

**Primary control is off-chain.** The on-chain tolerant family is defense in
depth. The primary control is an SDK golden-vector suite asserting every emitted
`Token.data` round-trips through decode for its declared type,
`refundRecipient != 0`, `tokensOut` non-empty with non-zero minimums, and
`start <= deadline`. (Tracked SDK- side; not yet landed at the time of writing.)

---

## 4. Changes since the internal audit's frozen tree (`24e93e4`)

All items below alter the executor's creation code and therefore every derived
intent address — they landed as one batch while nothing is deployed or funded.

1. **B1 (HIGH)** — `_sweep(Token,…)` reworked to raw-word reads with a tolerant
   length gate. The typed `abi.decode`s it previously performed were a permanent
   brick on both refund branches for committed trigger data shorter than 64
   bytes (96 for ERC1155) or with a dirty address word. **Changelog note,
   verbatim per the internal audit: the sub-64-byte case converts BRICK →
   recoverable-with-a-second- transaction, not BRICK → auto-refunded** — the
   malformed entry is skipped, the asset stays at the (now deleted and
   redeployable) address, and a keeper `sweep[]` entry recovers it. The
   dirty-address-word case fully auto-refunds via uint160 truncation.
2. **B2 (HIGH)** — `_tryTransfer(address,…)` no longer `abi.decode`s the
   returned bool (whose validity check reverts on any non-0/1 word):
   `success && (ret.length == 0 || (ret.length >= 32 && _word(ret, 0) == 1))`.
   `== 1` rather than `!= 0` because the helper also serves the strict fee path.
   The USDT/BNB zero-returndata class was always safe via the `ret.length == 0`
   arm.
3. **B3 (MEDIUM)** — zero `refundRecipient` beneficiary substitution (above).
4. **P8 (LOW)** — `_constrained` uses an explicit `after_ < before[i]`
   comparison, so a recipient balance decrease reverts `Insufficient` instead of
   Panic 0x11.
5. **Empty/zero `tokensOut` (MEDIUM)** — `_constrained` rejects
   `tokensOut.length == 0` and any entry whose minimum is 0 (liveness-zone
   revert). The floor is still 1 wei; the structural control is the B4 keeper
   requirement.
6. **P5 (was "out of scope", now in scope)** — ERC721 fixed end to end:
   `_amount` / `_tryAmount` return 1 (the second word is a tokenId, not a
   quantity); the approval revoke is a tolerated low-level call (EIP-721 rejects
   `approve` from a non-owner after the NFT legitimately moved); in-side
   presence semantics per §2.
7. **P11** — `getAddress(bytes)` deleted. The overload hashed caller bytes
   verbatim, handing out fundable addresses the factory could never deploy to
   (it always appends canonical `abi.encode(intent)`). `getAddress(Intent)` is
   deployment- consistent by construction.
8. **Structural** — the `TokenLib` library was dissolved: the executor now
   imports `Token`/`TokenType`/`IEnsoRouter` directly from
   `src/interfaces/IEnsoRouter.sol` (one canonical type; typed route calls
   compile against the real router interface) and carries all token accounting
   as private functions. `EnsoRouter` itself is untouched and out of scope
   (separately audited).

---

## 5. Known properties that change finding severity

- **Address reuse is real; success-path residue is recoverable.** EIP-6780
  deletes an account destroyed in its creating transaction at
  end-of-transaction, so the address is reusable across transactions. Residue
  left after a successful execute is recovered by re-running the same intent
  post-deadline (committed-trigger sweep or a keeper `sweep[]` entry). **Foundry
  artifact warning:** a second same-address CREATE2 in one test function fails
  with `CreateCollision` unless the test carries
  `/// forge-config: default.isolate = true`. Two earlier reviewers were misled
  by exactly this into "residue is permanently stranded" findings.
- **`MockIntentRouter` structurally cannot show the B4 over-pull** — it pulls a
  configured amount, while the real `EnsoRouter._transfer` pulls the full
  encoded amount into shared `EnsoShortcuts` unconditionally. Do not trust the
  in-repo unit suite on B4; the planned over-delivery test against the real
  router (asserting `balanceOf(shortcuts)` unchanged after a compliant route) is
  the only test shape that can catch it.
- **Over-long `Token.data` is fine.** Solidity's decoder enforces a minimum
  length and ignores trailing words; only short data or dirty address words were
  ever the failure class (and are now tolerated on refund paths).
- **`start > deadline` is not a defect** — `TooEarly` sits on the execute
  branch, so such an intent simply refunds at the deadline. SDK validation
  rejects it as nonsense; nothing to fix on-chain.

## 6. Test inventory

- 40 tests green at `b41ec65` (unit concrete + fuzz), `forge fmt` clean.
- Invariant fuzzes: `refundNeverReverts.t.sol` (4 properties × 1000 runs) — the
  executable form of §1. Recommended required in CI.
- Known remaining gaps (tracked, not blocking handoff): real-router
  over-delivery test (§5), zero-recipient assertion on the execute branch, an
  explicit USDT-shaped zero-return token case, the success-residue re-run pair
  under isolate mode, and the SDK golden-vector suite (§3, the primary control).

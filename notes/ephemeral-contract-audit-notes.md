# Ephemeral Intent Contracts — Auditor Notes

Prepared for the external (Dedaub) engagement. State as of commit `b41ec65`,
plus the uncommitted owner-privilege change recorded in §7 (the
`refundRecipient` → `owner` rename and the owner arms of the constructor).
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

Owner arms added after `b41ec65` (no pinned line numbers; see §7 for the branch
table):

- BRICK ZONE: the `keeper != intent.owner` branch test (pure) and the owner
  refund arm (`_refund`, tolerant family).
- LIVENESS ZONE, owner-only: the owner route arm (`_route` with owner-supplied
  bytes). Reachable only when the owner passes non-empty `route`; the owner
  always has the refund arm as a fallback, so a revert there is confined to the
  owner's own transaction. The refund-never-reverts fuzz carries two owner
  properties (committed trigger bytes, owner sweep list) for the refund arm.

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
  route), and skipped entirely when the keeper is the owner (§7) — the owner
  never pays themselves.

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
  check as a finding; it is a recorded decision. **The owner is not a third
  party**: since the owner-privilege change (§7) the owner can refund, sweep, or
  re-route at any block, inside the exclusive window included. The lock is
  against outsiders only.

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

**Beneficiary substitution, not validation** (`:56-60`): `owner == 0` (the field
was `refundRecipient` at `b41ec65`) substitutes the keeper everywhere (sweeps
and selfdestruct). A prologue `revert BadIntent()` was explicitly rejected — it
would brick the execute branch too, converting a conditional loss into an
unconditional one. A zero owner also never matches the keeper (the factory's
caller is never zero), so zero-owner intents cannot reach the owner arms of §7.

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
`Token.data` round-trips through decode for its declared type, `owner != 0`
**and `owner` is the end user's own address** (never the keeper, never a shared
contract — see §7, the field is now an authority), `tokensOut` non-empty with
non-zero minimums, and `start <= deadline`. (Tracked SDK- side; not yet landed
at the time of writing.)

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
3. **B3 (MEDIUM)** — zero `refundRecipient` (since renamed `owner`, §7)
   beneficiary substitution (above).
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

Post-`b41ec65`, from a subsequent adjudication round (both liveness-zone, both
ERC721):

9. **Scoped 721 revoke tolerance (LOW)** — the blanket tolerant revoke could
   swallow a failure while the executor STILL owned the token (a collection
   rejecting `approve(address(0), id)`), letting the approval outlive the
   EIP-6780 deletion into the address's next incarnation — contradicting the
   stated no-approval-outlives-the-call invariant. The revoke now probes
   `ownerOf` first: strict typed `approve(address(0), id)` while held (a revert
   is execute-branch liveness), tolerance only for the moved case where EIP-721
   makes a revoke impossible and unnecessary.
10. **In-side fee gate for 721 (INFO)** — `_payFee`'s strict arm previously read
    the out-side collection count for an ERC721 fee; both arms now use the
    ownership probe for the committed id. Outcome-neutral (the mismatch
    previously surfaced as `SendFailed` inside the transfer), fixed for semantic
    consistency with the direction-dependent second-word convention.

---

## 5. Known properties that change finding severity

- **Address reuse is real; success-path residue is recoverable.** EIP-6780
  deletes an account destroyed in its creating transaction at
  end-of-transaction, so the address is reusable across transactions. Residue
  left after a successful execute is recovered by re-running the same intent
  post-deadline (committed-trigger sweep or a keeper `sweep[]` entry), or at any
  time by the owner through the owner sweep/refund arms (§7). **Foundry artifact
  warning:** a second same-address CREATE2 in one test function fails with
  `CreateCollision` unless the test carries
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
- Owner arms (§7): `owner.t.sol` — owner refund inside the window, before start,
  and inside another keeper's exclusivity window; extra and duplicate sweep
  entries; owner route overriding the committed payload with no fee off the top
  and residue recoverable by a later owner refund; owner route under every
  closed gate and outside the window; owner route revert leaving the refund arm
  available; and two privilege-boundary contrasts (a third party's bytes are
  ignored in ROUTE mode, a zero owner elevates nobody). The fee-skip assertions
  count `Transfer` events, since with keeper == owner the final balances are the
  same whether or not a fee was paid. `refundNeverReverts.t.sol` gains two owner
  properties (committed trigger bytes, owner sweep list) at 1000 runs each. All
  ephemeral suites green with the change applied.

---

## 7. Owner privileges (post-`b41ec65`, uncommitted at the time of writing)

`Intent.refundRecipient` is renamed `owner` and becomes an authority, not just a
payee. When the factory's caller (`keeper`, the `msg.sender` of `executeIntent`,
recorded in transient context) equals `intent.owner`, the executor hands the
owner full control of the address. Only that address can satisfy the check: the
owner is inside the CREATE2 preimage and the factory records `msg.sender`
itself, so no route bytes, sweep entry, or nested call can forge it. Shortcut
commands run with `EnsoShortcuts` as sender and the executor's approvals go only
to the router and are revoked after the call, so an owner route cannot reach any
other intent's address either.

### Branch table (constructor, current tree)

The **standard path** is byte-for-byte the `b41ec65` logic apart from the rename
and the fee guard inside `_refund`. It is taken whenever the keeper is not the
owner. The **owner path** is mode-independent and has two verbs:

| route     | action                                                                                       |
| --------- | -------------------------------------------------------------------------------------------- |
| non-empty | `_route` with the owner's bytes over the committed triggers at live balance; `sweep` ignored |
| empty     | `_refund`: fee token, committed triggers, then the owner's `sweep` list; no fee              |

An owner who wants the committed ROUTE payload to run passes it as `route`; that
produces the same `_route` call minus the gates. Native residue rides the
selfdestruct to the owner on both arms. `_payFee` is skipped inside `_refund`
when keeper == owner, and the execute arm is unreachable for the owner, so the
owner never pays themselves; third-party keepers are paid exactly as at
`b41ec65`.

### Zone classification

- The `keeper != intent.owner` branch test is pure — brick zone, no reverts.
- The owner refund arm calls only `_refund` — the tolerant family, brick zone,
  no new reverts. Two fuzz properties (committed trigger bytes, owner sweep
  list) assert it never reverts inside the window.
- The owner route arm calls `_route` strictly. It is reachable only when the
  owner supplies non-empty `route`, and the owner always has the refund arm as a
  fallback, so a revert there is liveness-only and confined to the owner's own
  transaction.
- Third-party keepers cannot reach either owner arm, so nothing about their
  brick or liveness analysis changed.

### Trust-model consequences (recorded decisions, not findings)

1. **The owner can exit or re-route at any block**, inside
   `[start, exclusiveUntil]` included. The §2 lock holds against outsiders only.
   A keeper that hedges or commits capital before its transaction lands can be
   front-run by the owner's sweep or route; the keeper must treat inclusion as
   the only commitment point. This is the trust-model change §3 B4 says to
   reopen against, in the other direction: the user is trusted with their own
   funds, the keeper's execution is no longer guaranteed the funds.
2. **`owner` must be the end user's own address.** Setting it to the keeper's
   address gives the keeper unconstrained control of every branch. Setting it to
   a shared contract with open execution (a router, a receiver, a bridge
   callback contract) gives control to anyone who can make that contract call
   the factory. A zero owner stays safe (keeper substituted as beneficiary,
   owner arms unreachable).
3. **Owner routes are unvalidated by design.** No chain check, no window, no
   trigger minimums, no `Constrained` outcome floor, no `Exclusive()`.
   Wrong-chain routing is possible because the router shares its address on
   every chain.

### Limitations of the owner arms (documented, not bugs)

- The owner route approves and pulls every committed trigger at live balance. A
  missing ERC721 trigger makes the approve revert, and a zero-balance ERC20
  trigger issues a zero-amount `transferFrom` that some tokens reject; the owner
  falls back to the refund arm in those cases. Tokens that are not triggers
  cannot be routed, only swept.
- With `route` non-empty, `sweep` is ignored.
- The owner cannot run the committed payload under the gates; the gates exist
  against the keeper, and the owner passes the payload as `route` instead.
- A trigger listed again in `sweep` is harmless: the second pass reads a zero
  balance and skips, so the token moves once (asserted in `owner.t.sol`).

### Open items

- `EphemeralFactory.executeIntent` NatSpec still describes `route` as
  CONSTRAINED-only and `sweep` as refund-branch-only; both are also the owner's
  inputs now.
- Like §4, this changes the executor's creation code and therefore every derived
  intent address; it must land before anything is funded.

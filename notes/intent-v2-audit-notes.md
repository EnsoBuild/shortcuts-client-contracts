# Intent v2 Contracts — Auditor Notes

`notes/ephemeral-contract-audit-notes.md` is frozen: it describes the tree at
commit `b41ec65` and is never amended. This note carries every change since, so
the two files together describe the current tree. Design rationale for the new
format lives in `notes/intent-router.md`; this note is the review frame and the
decisions on record.

The changes come in two batches:

- **A — owner privileges** (committed, `96b0a98`): `Intent.refundRecipient` is
  renamed `owner` and becomes an authority. §1 lists the corrections this makes
  to the frozen note; §2 is the change itself.
- **B — shared intent format and `IntentRouter`** (uncommitted): one `Intent`
  struct for both contracts, the keeper as an intent field, and a new
  approval-based router. §3 onward.

Scope: `src/interfaces/IIntent.sol`, `src/interfaces/IIntentRouter.sol`,
`src/router/IntentRouter.sol`, `src/wallet/EphemeralIntentExecutor.sol`,
`src/factory/EphemeralFactory.sol`, `script/IntentRouterDeployer.s.sol`,
`script/EphemeralDeployer.s.sol`.

Read the frozen note's §1 severity model first. It still governs the ephemeral
executor completely, including every line added since: a revert reachable from
`_refund` or from the constructor prologue is a PERMANENT BRICK, a revert
confined to the execute arm is LIVENESS ONLY. The maintainer edit rules in that
section apply verbatim to the current tree.

---

## 1. Corrections to the frozen note

Each item below is a place where the frozen note's text no longer matches the
tree. Nothing else in it has changed.

1. **Header** — the frozen note's scope is `b41ec65`. The current tree is that
   plus batches A and B.
2. **§1 zone map** — the owner arms added by batch A classify as: BRICK ZONE for
   the `caller != intent.owner` branch test (pure) and the owner refund arm
   (`_refund`, tolerant family); LIVENESS ZONE, owner-only, for the owner route
   arm (`_route` with owner-supplied bytes), reachable only when the owner
   passes non-empty `route` and always backed by the refund arm, so a revert
   there is confined to the owner's own transaction. Batch B's line numbers have
   all moved; treat the frozen note's pinned numbers as `b41ec65` history, not
   as a map of the current file.
3. **§1 `_payFee` rule** — the fee is still paid FIRST on both branches, and is
   now skipped entirely inside `_refund` when the caller is the owner. The owner
   never pays themselves.
4. **§2 keeper model** — the exclusivity window (`exclusiveKeeper`,
   `exclusiveUntil`, `Exclusive()`) is gone; `intent.keeper` replaces it (§3 and
   §4 below). Two consequences of that section survive the replacement: the
   owner is **not** a third party (since batch A the owner can refund, sweep or
   re-route at any block, whatever the keeper field says), and the SDK-policy
   framing is superseded — a committed keeper is now contract law.
5. **§3 beneficiary substitution** — reads `owner == 0` now (the field was
   `refundRecipient` at `b41ec65`). The reasoning is unchanged, and a zero owner
   never matches the caller (the factory's caller is never zero), so zero-owner
   intents cannot reach the owner arms.
6. **§3 primary control** — the SDK golden-vector suite must now assert
   `owner != 0` **and that `owner` is the end user's own address** (never the
   keeper, never a shared contract — the field is an authority; see §2 below),
   on top of the existing round-trip, non-empty-minimums and `start <= deadline`
   assertions.
7. **§4 item 3 (B3)** — the zero-`refundRecipient` substitution is the same fix;
   the field is now `owner`.
8. **§5 residue recovery** — success-path residue is recoverable as described,
   and additionally at any time by the owner through the owner refund arm.
9. **§6 test inventory** — superseded by §7 below.

---

## 2. Batch A — owner privileges

`Intent.refundRecipient` is renamed `owner` and becomes an authority, not just a
payee. When the factory's caller equals `intent.owner`, the executor hands the
owner full control of the address. Only that address can satisfy the check: the
owner is inside the CREATE2 preimage and the factory records `msg.sender`
itself, so no route bytes, sweep entry, or nested call can forge it. Shortcut
commands run with `EnsoShortcuts` as sender and the executor's approvals go only
to the router and are revoked after the call, so an owner route cannot reach any
other intent's address either.

### Branch table (constructor)

The **standard path** is taken whenever the caller is not the owner; it is the
`b41ec65` logic apart from the rename, the fee guard inside `_refund`, and batch
B's changes in §4. The **owner path** has two verbs:

| route     | action                                                                                         |
| --------- | ---------------------------------------------------------------------------------------------- |
| non-empty | `_route` with the owner's bytes over the committed `tokensIn` at live balance; `sweep` ignored |
| empty     | `_refund`: fee token, committed `tokensIn`, then the owner's `sweep` list; no fee              |

An owner who wants the committed route to run passes it as `route`; that
produces the same `_route` call minus the gates. Native residue rides the
selfdestruct to the owner on both arms. `_payFee` is skipped inside `_refund`
when the caller is the owner, and the execute arm is unreachable for the owner,
so the owner never pays themselves; third-party callers are paid exactly as at
`b41ec65`.

### Zone classification

- The `caller != intent.owner` branch test is pure — brick zone, no reverts.
- The owner refund arm calls only `_refund` — the tolerant family, brick zone,
  no new reverts. Two fuzz properties (committed `tokensIn` bytes, owner sweep
  list) assert it never reverts inside the window.
- The owner route arm calls `_route` strictly. It is reachable only when the
  owner supplies non-empty `route`, and the owner always has the refund arm as a
  fallback, so a revert there is liveness-only and confined to the owner's own
  transaction.
- Third-party callers cannot reach either owner arm, so nothing about their
  brick or liveness analysis changed.

### Trust-model consequences (recorded decisions, not findings)

1. **The owner can exit or re-route at any block**, including inside the window
   a keeper expects to own. A keeper that hedges or commits capital before its
   transaction lands can be front-run by the owner's sweep or route; the keeper
   must treat inclusion as the only commitment point. This is the trust-model
   change the frozen note's §3 B4 says to reopen against, in the other
   direction: the user is trusted with their own funds, and the keeper's
   execution is no longer guaranteed the funds.
2. **`owner` must be the end user's own address.** Setting it to the keeper's
   address gives the keeper unconstrained control of every branch. Setting it to
   a shared contract with open execution (a router, a receiver, a bridge
   callback contract) gives control to anyone who can make that contract call
   the factory. A zero owner stays safe (caller substituted as beneficiary,
   owner arms unreachable).
3. **Owner routes are unvalidated by design.** No chain check, no window, no
   `tokensIn` minimums, no outcome floor, no keeper check. Wrong-chain routing
   is possible because the router shares its address on every chain.

### Limitations of the owner arms (documented, not bugs)

- The owner route approves and pulls every committed `tokensIn` entry at live
  balance. A missing ERC721 entry makes the approve revert, and a zero-balance
  ERC20 entry issues a zero-amount `transferFrom` that some tokens reject; the
  owner falls back to the refund arm in those cases. Tokens that are not
  committed cannot be routed, only swept.
- With `route` non-empty, `sweep` is ignored.
- The owner cannot run the committed route under the gates; the gates exist
  against the keeper, and the owner passes the bytes as `route` instead.
- A committed token listed again in `sweep` is harmless: the second pass reads a
  zero balance and skips, so the token moves once (asserted in `owner.t.sol`).

---

## 3. Batch B — shared intent format

One struct, `Intent` in `src/interfaces/IIntent.sol`, is both the EIP-712
message `IntentRouter` executes and the blob inside the ephemeral executor's
CREATE2 address. `Constrained`, `Mode` and the executor-local `Intent` /
`KeeperFee` are gone.

| `b41ec65` ephemeral                                   | v2 shared                                                            |
| ----------------------------------------------------- | -------------------------------------------------------------------- |
| `refundRecipient`                                     | `owner` (batch A; an authority, not just a payee)                    |
| `triggers`                                            | `tokensIn` (same in-side semantics)                                  |
| `mode` + `bytes payload`                              | `bytes route`: non-empty = committed, empty = keeper-routed          |
| `Constrained.recipient`, `.tokensOut`                 | top-level `recipient`, `tokensOut`                                   |
| `Constrained.exclusiveKeeper/exclusiveUntil`          | `keeper`; `address(0)` permits any caller                            |
| `Exclusive()`, `Insufficient()`                       | `NotKeeper()`, `Unconstrained()`, `AmountTooLow(token, amount, min)` |
| `version, chainId, nonce, start, deadline, keeperFee` | unchanged                                                            |

- Mode is derived from `route`, so the two `b41ec65` knobs cannot disagree and
  every field is visible to an EIP-712 signer instead of hiding inside `bytes`.
- `keeper` is who may execute. A non-zero keeper is checked against the caller
  on the execute path of both contracts, for committed and keeper routes alike.
  Zero means permissionless execution: the outcome floor is then the owner's
  only protection and the intent fee pays whoever lands the intent.
- `Token` conventions are EnsoRouter's, unchanged from the frozen note's §2:
  in-side ERC721 second word is a tokenId, out-side ERC721 second word is a
  minimum count, ERC1155 is `(token, id, amount)`.
- `KeeperFee` is unchanged in shape and is paid to the executing caller.
  `IntentRouter` honours `intentFee` and ignores `refundFee` (it has no refund
  branch). The ephemeral honours both as before.

---

## 4. Batch B — ephemeral executor and factory

Behavioural changes, all inside the execute arm:

- The keeper gate is
  `intent.keeper != 0 && caller != intent.keeper → NotKeeper()`, placed after
  the `TooEarly` check and before the delivery check and the fee. Unlike
  `Exclusive()`, which lived inside the CONSTRAINED arm only, it covers
  committed routes too; a committed route that should be permissionless carries
  `keeper == 0`. It sits inside the `caller != intent.owner` arm, so it never
  applies to the owner.
- A single `_run` serves both routes, replacing `_constrained`. A keeper route
  (`intent.route` empty) requires `tokensOut` non-empty. In either mode every
  `tokensOut` entry must carry a non-zero minimum and is checked against the
  recipient delta, so a committed route may carry an optional floor (ROUTE mode
  had none).
- Refund branches and the owner arms are unchanged and remain permissionless:
  the keeper gate never applies to them, so refunds stay self-incentivizing.
- `EphemeralFactory.executeIntent` is `nonReentrant` (OpenZeppelin
  `ReentrancyGuardTransient`). A nested `executeIntent` from inside a route now
  reverts instead of overwriting the transient context; the executor still reads
  `context()` once, first. `context()` returns `(route, sweep, sender, router)`
  and the executor names the factory's `msg.sender` `caller` — the frozen note
  calls that value `keeper`, which now means the intent field instead. The
  factory constructor still takes `router` only.

Zone classification: `NotKeeper`, `Unconstrained` and `AmountTooLow` sit on the
execute arm only — liveness. The reentrancy guard can only revert a nested
`executeIntent`, which is reachable only from a route, so it too is execute-arm
liveness. The constructor prologue, branch selection, owner arms and the
tolerant family are logically untouched apart from the `triggers → tokensIn`
rename; `refundNeverReverts.t.sol` passes unchanged in substance.

Resolved by this batch:

- The frozen note's §5 warning that "a nested `executeIntent()` in the same
  transaction overwrites the factory's transient context" is no longer
  reachable; the nested call reverts.
- Batch A left `executeIntent`'s NatSpec describing `route` as CONSTRAINED-only
  and `sweep` as refund-branch-only, when both are also the owner's inputs.
  Rewritten.

Like the frozen note's §4, both batches change the executor's creation code and
therefore every derived intent address. They must land before anything is
funded, and the backend / alpha-scanners codecs must move to the v2 tuple at the
same time. The factory address space still forks per router only.

---

## 5. Batch B — IntentRouter

`IntentRouter` holds no funds at rest. Users approve it; the caller submits
`executeIntent(intent, signature, route)`; tokens move from `intent.owner` into
the router's own `EnsoShortcuts` (deployed in the constructor, exactly as
`EnsoRouter`), the route runs, and the recipient deltas are checked. There is no
brick zone — every revert is a plain transaction revert for the caller — so the
frozen note's severity model does not apply here. The property to audit is the
authorization model, which has three legs:

1. **Who may call.** `intent.keeper`, or anyone when it is zero. The intended
   keeper is the chain's `KeeperWallet` (`Ownable2Step` with executors), so
   signer rotation happens there and the router holds no keeper state.
   `executeIntent` is `nonReentrant`.
2. **Whose funds, and how much.** The EIP-712 digest of the full `Intent` must
   verify for `intent.owner` — ECDSA first (EOAs and EIP-7702 accounts), then
   ERC-1271. The router moves tokens only in two places, both from `owner`:
   `_payFee` (`intentFee`, to `msg.sender`) and the `tokensIn` pull loop (exact
   committed amounts). `EnsoShortcuts` holds no allowance from any user, so a
   route cannot reach the owner's wallet.
3. **How often.** Unordered nonce bitmap per owner (`nonce >> 8` word,
   `1 << (nonce & 0xff)` bit), consumed before any external call;
   `cancel(nonce)` retires one. `start`/`deadline` inclusive window;
   `intent.chainId` is checked explicitly and bound a second time by the EIP-712
   domain.

Outcome check: `tokensOut` balances are snapshotted at `recipient` after the
pulls, so `recipient == owner` with `tokenIn == tokenOut` measures what the
route delivers rather than the net. A keeper route with empty `tokensOut`
reverts `Unconstrained`; a zero minimum reverts `Unconstrained` in either mode;
a recipient balance decrease reports zero delivered via `AmountTooLow`, never a
Panic.

### Decisions on record (not findings)

- **Keeper trusted when named; the floor is a floor.** B4 from the frozen note's
  §3 applies unchanged: `EnsoShortcuts` is shared across intents, surplus a
  route leaves behind is first-come-first-served, and the written keeper
  requirement to size consumption from `balanceOf(shortcuts)` carries over.
- **`keeper == 0` is the owner's choice of a permissionless caller.** The caller
  then controls the route and keeps whatever clears the floor; the owner's
  protection is the minimums they signed. Do not file "an arbitrary caller can
  extract surplus from a keeperless intent" as a finding; it is the stated
  meaning of the field. The SDK is expected to set a keeper by default.
- **Reentrancy guards on both entry points.** Without them, a keeperless route
  could execute a second intent to the same recipient mid-flight and count one
  delivery toward two floors. The guards close the intra-contract case; the
  cross-contract case (a route in one contract executing an intent in the other)
  remains part of the keeperless trust model above.
- **`refundFee` is ignored, not rejected.** Rejecting it would block an intent
  the user signed over a field that cannot apply; ignoring it only ever favours
  the user.
- **Native `tokensIn` and a native `intentFee` revert** `UnsupportedTokenType`:
  nothing can be pulled from a wallet, and `executeIntent` is non-payable so
  caller value never enters. Native `tokensOut` is supported.
- **`version` is not enforced on-chain.** The EIP-712 domain version pins the
  hashing format; the struct field is informational and part of the hash.
- **ECDSA before ERC-1271.** OZ 5.2 `SignatureChecker.isValidSignatureNow` skips
  ECDSA for any account with code, which would reject EIP-7702 accounts signing
  with their key. The router follows `EnsoReceiver`'s order.
- **Committed route plus `tokensOut`** enforces the floor as well; strictly more
  protection than ROUTE mode had.
- **Call surface** is `shortcuts.call(data)` with no selector restriction, the
  same as `EnsoRouter._execute`. `EnsoShortcuts` exposes `executeShortcut`,
  `receive`, and the ERC721/ERC1155 holder callbacks.

### Where we want attention

- The EIP-712 encoding of nested `Token[]` and `KeeperFee` and of `bytes route`,
  and that the field order of the type string matches the struct. `hash.t.sol`
  pins a digest produced by ethers v6 `TypedDataEncoder` for a representative
  intent with every token type, a keeper and a committed route; it is the only
  external check on the type string.
- The nonce bitmap arithmetic and the cancel path.
- `_minOut` decoding ERC20 and ERC721 through one `(address, uint256)` arm, and
  the ERC1155 arm; it must agree with `EnsoRouter._checkMinAmountOut`.
- A hostile owner contract that returns the ERC-1271 magic for any hash can only
  authorise the spending of its own approvals.
- The keeperless path end to end: whether any route shape lets a permissionless
  caller take more than the floor leaves, beyond the surplus the model already
  concedes.

---

## 6. Deployment

- `IntentRouterDeployer` is salted CREATE2 (`"IntentRouter"`) with no
  constructor arguments; the constructor deploys the router's `EnsoShortcuts`.
- `EphemeralDeployer` is unchanged (router map, salted factory).
- Neither contract carries a keeper; the keeper is set per intent by the SDK.

---

## 7. Test inventory

Supersedes the frozen note's §6.

- **Batch A**, `owner.t.sol`: owner refund inside the window and before start;
  owner refund on a keeper-routed intent, leaving the keeper nothing to execute;
  extra and duplicate sweep entries; owner route overriding the committed route
  with no fee off the top and residue recoverable by a later owner refund; owner
  route under every closed gate and outside the window; owner route revert
  leaving the refund arm available; and two privilege-boundary contrasts (a
  third party's bytes are ignored on a committed route, a zero owner elevates
  nobody). The fee-skip assertions count `Transfer` events, since with caller ==
  owner the final balances are the same whether or not a fee was paid.
  `refundNeverReverts.t.sol` carries two owner properties (committed `tokensIn`
  bytes, owner sweep list) at 1000 runs each alongside the original four.
- **Batch B**, ephemeral: `route.t.sol` (committed route, the keeper gate on it,
  and the optional floor), `constrained.t.sol` (keeper route, the keeper gate
  and the keeperless path), `refund.t.sol` (including a permissionless refund),
  factory suites with a constructor test and a nested-`executeIntent` test.
- **Batch B**, `test/unit/concrete/router/intentRouter/`: constructor,
  `executeIntent`, cancel, and the golden-vector `hash` test (router placed at a
  fixed address with `deployCodeTo` so the digest is comparable). The
  `executeIntent` tests run real `EnsoShortcuts` weiroll routes and cover every
  gate, the keeperless path, an ERC-1271 wallet, an etched-code owner signing
  with its key, NFT and ERC1155 legs, the fee, a reverting route, and reentry.
- All ephemeral, factory, fuzz and router suites green; `forge fmt` and
  `forge lint` clean on every file in scope.
- Test note: signing reads `hash()` from the router, so revert tests must sign
  before `vm.expectRevert` or the expectation attaches to the view.

---

## 8. Open items

- `foundry.toml` still lists the executor under "already audited" in the fmt and
  lint ignore lists; it was hand-formatted for these changes.
- Backend and alpha-scanners codecs encode the `b41ec65` tuple, so they are
  behind both batches. They must move to the v2 tuple and to the EIP-712 `types`
  in `notes/intent-router.md` before anything is funded or signed, and must set
  `keeper` deliberately — an omitted field encodes as zero, which means
  permissionless.
- Carried over from the frozen note's §6: the real-router over-delivery test,
  the zero-recipient assertion on the execute branch, an explicit USDT-shaped
  zero-return token case, the success-residue re-run pair under isolate mode,
  and the SDK golden-vector suite (the primary off-chain control).

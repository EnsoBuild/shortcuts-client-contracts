# Intent Constraints — Auditor Notes

`notes/ephemeral-contract-audit-notes.md` and `notes/intent-v2-audit-notes.md`
are frozen and never amended. The v2 note describes the tree at commit
`1ace556`. This note covers every change since then:

- the constraint language, which replaces the v2 struct's `tokensIn` /
  `tokensOut` / `route` model;
- Merkle intent trees;
- bridge guardians and keeper-funded messaging fees;
- an intent lock shared by the factory and the router;
- usage counters and execution records;
- the deterministic deployers.

Read the three notes together for the full picture. Where this note and an older
one disagree, this note wins. §1 lists the places where the v2 note no longer
matches the code.

Scope:

- `src/interfaces/IIntent.sol`, `IEphemeralFactory.sol`, `IIntentLock.sol`,
  `IIntentRouter.sol`, `IIntentGuardian.sol`, `IIntentCounter.sol`,
  `IIntentOracle.sol`, `bridges/ITokenMessengerV2.sol`,
  `bridges/IAcrossSpokePool.sol`
- `src/libraries/IntentEvaluator.sol`, `IntentHash.sol`, `IntentRecord.sol`
- `src/wallet/EphemeralIntentExecutor.sol`, `src/factory/EphemeralFactory.sol`
- `src/router/IntentRouter.sol`
- `src/intent/BridgeGuardian.sol`, `src/intent/IntentCounter.sol`
- `script/IntentDeployment.sol`, `BridgeConfig.sol`, `EphemeralDeployer.s.sol`,
  `IntentDeployer.s.sol`, `IntentRouterDeployer.s.sol`,
  `IntentCounterDeployer.s.sol`, `BridgeGuardianDeployer.s.sol`,
  `IntentDeploymentsWriter.s.sol`

The ephemeral note's §1 severity model still governs the executor:

- **Brick zone.** A revert reachable from the constructor prologue or from
  `_refund`, for every caller, is a PERMANENT BRICK.
- **Liveness only.** A revert confined to the execute arm or the owner route arm
  only fails that one transaction.

`IntentRouter` holds no funds between transactions. It has no brick zone.

---

## 1. Corrections to the v2 note

1. **Header.** The current tree is `1ace556` plus everything in this note.
2. **§3 shared format.** `Intent` keeps `version`, `chainId`, `nonce`, `start`,
   `deadline`, `owner` and `keeper`, and adds `exclusive` and `constraints`.
   `tokensIn`, `tokensOut`, `recipient`, `route` and `keeperFee` are gone; §3
   below replaces them. `version` is now enforced.
3. **§2 owner arms.**
   - The owner route runs `routes[0]` over every rule input, at its live
     balance, through the leaf's router (or the caller's router when the leaf
     names none).
   - The owner refund arm returns the refund list, every rule input and the
     owner's sweep list.
   - The owner still never pays a fee.
   - The limitations in that section still hold, read against rule inputs
     instead of `tokensIn`.
4. **§4 executor and factory.**
   - `_run` and the `tokensOut` floor are gone.
   - The keeper gate now lives in the evaluator (§3.1).
   - `context()` returns `(execution, sender, domain)`.
   - The factory takes no constructor arguments.
   - `nonReentrant` is replaced by the shared intent lock (§4).
   - `executeIntent` and the executor's constructor are payable, for the
     keeper's messaging fees (§3.12).
5. **§5 IntentRouter.**
   - The router no longer deploys its own `EnsoShortcuts`. It pulls inputs into
     itself and approves an EnsoRouter for each route.
   - The router's constructor takes the chain's `EphemeralFactory`, whose lock
     it shares. `nonReentrant` is gone.
   - The nonce bitmap is replaced by per-`(owner, nonce)` execution records with
     lifetimes. `cancel` takes an array.
   - `executeIntent` is payable, for the keeper's messaging fees.
   - `refundFee` no longer exists.
   - The signature path (ECDSA, then ERC-1271) is unchanged.
6. **§6 deployment, §7 tests, §8 open items.** Superseded by §7, §10 and §11
   below.
7. **Design rationale.** The v2 note points to `notes/intent-router.md`, which
   describes the replaced format. This note is the reference for the current
   design.

---

## 2. Architecture

Each `Intent` covers one chain. The router executes one signed `Intent`. An
ephemeral tree may hold several leaves for the same chain, plus an optional
default leaf (`chainId 0`). The executor runs whichever leaf the caller proves
for the current chain, and the caller chooses which. A chain's leaves share the
address's execution record and its counter key, both of which are keyed by the
root. So:

- a `ONCE` lifetime is used up by whichever leaf executes first;
- `MATCH_FIRST` order holds only within a leaf;
- two leaves consuming the same asset let the keeper choose which one takes it.

The two contracts hold an intent's funds differently:

|                            | Ephemeral (`EphemeralFactory` + executor)         | `IntentRouter`                           |
| -------------------------- | ------------------------------------------------- | ---------------------------------------- |
| Authorization              | the address: CREATE2 over a Merkle root of leaves | the owner's EIP-712 signature            |
| Holder of funds            | the intent address itself                         | the owner's wallet, via approvals        |
| Leaf / digest              | `keccak256(keccak256(abi.encode(intent)))`        | `hashTypedData(IntentHash.hash(intent))` |
| Intent id (`Run.id`)       | `keccak256(0x1901 ‖ factory domain ‖ leaf)`       | the EIP-712 digest                       |
| Counter key (`Run.record`) | the root                                          | the digest                               |
| Execution record           | `EphemeralFactory.records[executor]`              | `IntentRouter.records[owner][nonce]`     |
| Non-OK status              | refund at once                                    | revert `Rejected(status)`                |

`IntentEvaluator` holds all constraint semantics. It is an external library, run
by `delegatecall`, so every approval, transfer and call is made as the calling
contract. Both contracts call `evaluate(intent, run)`. It takes the intent as
calldata and decodes it into memory once:

- the router passes its own calldata;
- the executor passes the copy it decoded from the factory's context.

The library receives the same ABI bytes either way. The `Run` struct supplies
what differs between them:

- `holder` is the intent address or the owner.
- `pull` is true for the router, which pulls inputs from the holder first.
- `records` is set for ephemeral records.
- `value` is the keeper's call value (§3.12).
- The caller supplies `router`, `routes` and `contexts`.

`evaluate` returns one of:

- `OK`.
- `MALFORMED`, `UNSUPPORTED` or `CUSTODIAL`: from the static check.
- `UNBOUNDED` (5): from the runtime custody test (§3.6).
- `EXHAUSTED`: from the ephemeral records.

Every non-OK status means nothing has moved. Liveness failures revert
(`NotKeeper`, `TooEarly`, `NotYet`, and anything execution raises).

`IntentHash.hash` is the EIP-712 struct hash. It reads the intent in place from
calldata and decodes nothing. `IntentHash.leaf` is internal, so proof
verification depends on no deployed library.

---

## 3. The constraint language

The format is in `IIntent.sol`. `Codes` values are part of the signed format.

### 3.1 Gates, in order

1. The static `check`. It never reverts: every index is bounds-checked, and a
   failure returns a status. `version != 2` gives `UNSUPPORTED`.
2. The keeper gate. If `keeper != 0`, the caller must be the keeper, until
   `exclusive` (when it is non-zero) has passed. With `exclusive == 0`, the
   keeper is exclusive for the intent's whole life.
3. `start`.
4. The execution record (§3.9). For the router, this check runs before
   `evaluate`.
5. Execution.

The deadline is checked by the callers. Past the deadline, the ephemeral
executor refunds and the router reverts `Expired`.

### 3.2 Not executed by this version

The following are reported `UNSUPPORTED`:

- attestation of any kind: `ATTESTED` sources, and predicates with
  `enforce != ONCHAIN`;
- trace patterns, and `CMP_EMITS` / `CMP_NEVER`;
- ERC1155 inputs without a committed router.

The last one is refused because ERC1155 approval is collection-wide, and the
approval would go to a router the keeper chooses.

### 3.3 Rules, inputs and consumption

- **Inputs.** A rule lists `inputs` (asset, minimum, optional price source) and
  a `threshold`, k of n.
- **Present.** An input is present when the holder's pre-execution holding is at
  least its minimum, and is non-zero when the minimum is zero. ERC721 presence
  means the holder owns the committed token id.
- **Active.** A rule is active when its present inputs reach the threshold and
  its `when` guard holds. A rule with no inputs depends on its guard alone.
  - `MATCH_ALL` activates every qualifying rule.
  - `MATCH_FIRST` stops at the first one.
  - No active rule reverts `NotExecutable`.
- **Routes need inputs.** A rule with `routing != ROUTE_NONE` and no inputs is
  `MALFORMED`. A route runs as the router or the intent address, never as the
  owner, so it would have nothing to spend.
- **Asset overlap.** An asset appears at most once per rule. Under `MATCH_ALL`,
  it appears in at most one rule. So active rules never share an input asset,
  and per-asset state is unambiguous.
- **Outcome overlap.** Under `MATCH_ALL`, two rules may not name the same
  handoff, and their `then` comparisons may not read the same asset's `DELTA` or
  the same post-state view. Either gives `MALFORMED`. Otherwise one delivery
  could satisfy two rules. The key is the asset, not the account, so two rules
  that pay one asset to two accounts are also refused.
- **Size.** `check` caps handoffs at 256, and assets plus views at 256.
- **Consumption.** `EXACT` consumes the input's minimum. `DRAIN` consumes the
  whole pre-execution holding.
- **Partial thresholds.** A `ONCE` intent whose threshold is below its input
  count must `DRAIN`. Otherwise a keeper could take the profitable input and
  strand the rest.

### 3.4 Terms and phases

Terms are an ordered list in which every operand comes before the term that uses
it, so evaluation needs no cycle detection. Arithmetic is `int256`:

- `MUL` is `a·b/1e18`, `DIV` is `a·1e18/b`, `MUL_BPS` is `a·value/10000`.
- Converting an unsigned value above `int256` max reverts `Overflow`.
- Overflow inside arithmetic panics.

Each term is in one of three phases:

- **Post-state:** `DELTA`, `POST_VIEW`, and any term built on one of them.
- **Scoped:** `CONSUMED_VALUE` and anything built on it. The value depends on
  the rule, so it is memoized per rule.
- **Pre-state:** everything else: `CONST`, `NOW`, `BALANCE`, `PRE_VIEW`,
  `SOURCE` (oracle or counter) and `CONSUMED`.

Phase rules:

- `DELTA` baselines are snapshotted before rule selection, so before fees.
- **Pre-state is frozen.** Right after rule selection, `_freeze` computes and
  memoizes, for each active rule:
  - the fee candidate that `_payFees` will pick;
  - each accepted handoff's `minAmount` and `deadline`;
  - each counter write's amount;
  - both sides of every `then` comparison.

  For a post-state term, it computes the term's pre-state operands. Terms are
  memoized at first evaluation, so without this step a pre-state term first read
  after the routes would read post-execution state. Every term an active rule
  references is therefore computed before anything moves, including terms in OR
  groups whose other members have already failed.

- Reading a post-state term before the routes and handoffs finish reverts
  `NotExecutable`.

### 3.5 Predicates

- `then` predicates are ORed by `group`; predicates in the same group are ANDed.
- `when` guards follow the same grouping. They may only use comparisons, on
  terms that are pre-state and don't depend on what the rules consume. So the
  set of active rules is fixed before the keeper acts.
- `CMP_ACCEPTED` holds when its handoff was accepted.
- `CMP_CONSUMED_WITHIN` names a `Consume`. The counter is written only for the
  lowest passing group, and the counter itself reverts `CapExceeded`.
- No passing group reverts `PredicateFailed(rule)`.

### 3.6 Routing and the custody test

| `routing`         | Bytes that run                     | Notes                               |
| ----------------- | ---------------------------------- | ----------------------------------- |
| `ROUTE_NONE`      | none; any keeper bytes are ignored | inputs go only to fees and handoffs |
| `ROUTE_COMMITTED` | `rule.route`                       | needs `constraints.router != 0`     |
| `ROUTE_KEEPER`    | `routes[r]` from the caller        | the custody test applies            |

A route calls `routeSingle` or `routeMulti` on the router, with each present
input at its consumed amount less any fee paid in that asset. Each input is
approved immediately before the call and revoked immediately after.

The custody test applies to `ROUTE_KEEPER` rules only. It runs in two halves:

- **Static (`_bounded`).** Every OR group of `then` must contain either a
  handoff acceptance or a lower bound (`GTE`, `GT` or `EQ`) with a post-state
  left side and a pre-state right side. Failing gives `CUSTODIAL`.
- **Runtime (`_positive`).** That right side must be positive. A `GT` bound may
  also be zero. A spend cap (a negative floor) bounds nothing. Comparisons whose
  right side is post-state are skipped, as the static half skips them. A handoff
  acceptance counts only when the handoff's frozen `minAmount` is above zero.
  Failing gives `UNBOUNDED`.

The test is structural. It checks that a bound exists, not what the bound
measures.

Separately from the custody test, any accepted handoff whose frozen `minAmount`
is zero or below reverts `NotExecutable`.

### 3.7 Fees

- **Rule with inputs.** It pays its first fee candidate whose asset is a present
  input. A fee at or above what the rule consumes of that asset reverts.
- **Rule without inputs.** It has at most one candidate, paid from the holder.
- **No record.** When the lifetime keeps no record, the leaf can run again at
  once. A rule with a fee must then route its inputs or hand one of them off;
  otherwise `check` gives `CUSTODIAL`. This includes every rule with a fee and
  no inputs.
- **Skipped fees.** A non-positive fee is skipped, never inverted. If no
  candidate is present, the keeper goes unpaid.
- **Payee.** Fees go to `run.caller` and are paid before any route.

### 3.8 Handoffs and guardians

A `CMP_ACCEPTED` predicate on an active rule hands an asset to a guardian. The
guardian is `sources[h.source].target`, and its live `level()` must equal the
level committed in the source's config, or the call reverts `WrongLevel`.

**Amount handed over:**

- On a rule that runs no route, when the asset is one of its present inputs:
  what the rule consumes, less its fee in that asset.
- Otherwise: the executing contract's whole balance of the asset, which is
  whatever the route left.

**Obligation.** It is built entirely from committed data:

- the destination chain, method (zero = any), recipient and refund address;
- the delivered asset's token;
- `minAmount` and `deadline`, from the frozen terms, clamped at zero;
- a `deadline` above `uint64` max is clamped to that maximum.

**Call.**
`accept(intentHash, owner, keeper, token, amount, obligation, context)`, where
`owner` is `run.owner`, `keeper` is `run.caller`, and `context` is `contexts[i]`
from the keeper. The first word of the context is the handoff's messaging fee
(§3.12); the rest holds the method's own parameters.

**Native value sent with `accept`:** the amount when the input is native, plus
the handoff's fee share. Nothing else of the holder's native is forwarded.

### 3.9 Lifetimes and records

`IntentRecord` packs `window | count << 64` into one word.

| Lifetime                   | Behaviour                                                                                                  |
| -------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ONCE`                     | runs once                                                                                                  |
| `STANDING` with `interval` | at most once per window; windows are anchored at `start`, so a late execution doesn't move the next window |
| `STANDING` with `count`    | at most `count` executions                                                                                 |
| `STANDING` with neither    | keeps no record (deposit addresses)                                                                        |

A window of `uint64.max` is terminal, meaning cancelled. The ephemeral verdict
is checked before execution and written after it. The router writes its record
before evaluating, and any revert undoes the write.

### 3.10 Counters, oracles, views

- **`IntentCounter`** keys usage by `msg.sender`, so each writer can only touch
  its own entries. The executor's address is unique to its root, and the router
  keys entries by digest.
  - Counter windows are `timestamp / period`, aligned to the epoch. Lifetime
    windows are anchored at `start`.
  - A `SOURCE` counter term reads the executing contract's own usage.
- **Oracles.** `IIntentOracle.read(intentId, base, quote, "")` returns a WAD
  price and an `asOf` time. An `asOf` in the future, or older than the source's
  `staleness`, reverts `Stale`.
- **Views.** A view `staticcall`s `selector ‖ args` and reads one 32-byte word.
  A failed call or short return data reverts `ViewFailed`.

### 3.11 Strict frame

With `FRAME_STRICT`, after execution:

- No named asset on this chain may have dropped at the holder by more than the
  active rules consume, plus the fees of rules without inputs.
- No ERC20 approval granted during the run may remain.

Some limits apply:

- At an ephemeral holder, native is exempt.
- ERC721 frames count the whole collection, because outcome token ids may be
  newly minted.
- ERC721 and ERC1155 approvals are not re-checked here. They are revoked
  explicitly.

### 3.12 Messaging fees

Some delivery methods (CCIP, LayerZero, Ethereum → Arbitrum) charge a native fee
on top of the bridged amount. The keeper pays it as the call value of
`executeIntent`, on either carrier.

**Flow.**

1. `Run.value` carries `msg.value` into `evaluate`.
2. `_execute` writes it to the transient `RESERVED_SLOT` before the snapshot.
3. `_handoff` reads the fee as the first word of `contexts[i]`. A context
   shorter than 32 bytes means a fee of zero.
   - A fee above the reserve reverts `WrongValue`.
   - Otherwise the reserve drops by the fee, and `accept` is sent
     `(native input ? amount : 0) + fee`.
4. After the handoffs, a non-zero reserve reverts `WrongValue`. The shares must
   add up to `msg.value` exactly.
5. When `_positive` refuses (the run returns `UNBOUNDED`), the reserve is reset
   to zero. The executor then hands the value back to the caller.

**Separation.** `_balanceOf(NATIVE, address(this))` subtracts the reserve. The
keeper's unspent value is therefore never counted as the holder's native: not
for presence, consumption, deltas or the frame. A native input can share a
handoff with a fee. On the router path the holder is the owner, so only the
router's own native reads are affected.

**Guardians.** A guardian returns unused fee value, and any later refund of it
by the method, to `keeper`, never to `msg.sender`. The caller may be an intent
address, whose native is the owner's.

**Encoding.** The fee rides in the context rather than a separate `values`
array. This costs fewer evaluator bytes and leaves `Execution` and the router's
`executeIntent` arguments unchanged.

**Native-token chains.** On chains whose native coin is also an ERC-20 at an
address (Celo, Polygon's `0x…1010`, Arc's USDC), the keeper's value also shows
as the holder's token balance, which the reserve doesn't cover. Keepers send no
value there. With no value sent, a USDC handoff on Arc forwards none.

---

## 4. Ephemeral executor and factory

The executor's whole lifecycle runs in its constructor, which ends in
`selfdestruct`. The address is reusable, and its record survives.

### Factory

- **`executeIntent(root, execution)`.**
  - It is payable and permissionless.
  - It enters the shared intent lock (below) and exits it at the end.
  - It checks that the top-level ABI head offset is `0x40`, else it reverts
    `NonCanonicalEncoding`.
  - It stores the caller's own calldata encoding of `Execution`, plus
    `msg.sender`, in transient storage in 32-byte chunks.
  - It then creates the executor with CREATE2, forwarding `callvalue()`. The
    init code is the executor's creation code plus `abi.encode(root)`, with
    salt 0.
  - A constructor revert is bubbled up.
- **`context()`** returns that data plus the factory's EIP-712 domain separator.
- **`record()`** writes only the calling executor's own entry.

**Shared intent lock.** The factory implements `IIntentLock` (`enter`, `exit`,
`Locked`). The router holds the factory as its `lock`. The transient slot is
`keccak256("enso.intent.lock")`, and it holds the holder's address.

- **Entering.** `executeIntent` enters with the factory itself as holder. The
  router calls `enter()`, which enters with `msg.sender` as holder.
- **Taken.** Entering while the slot is set reverts `Locked`.
- **Releasing.** `exit()` and the factory's own exit clear the slot only when
  the caller is the holder. A route can't release a lock it doesn't hold.
- **Permissionless.** Anyone can enter. A lock taken in a transaction blocks
  only that transaction, so the only one it can grief is the caller's own.
- **Effect.** One intent executes at a time in a transaction, across both
  carriers. A route can't run another intent, ephemeral or router, inside its
  own.

### Constructor

The constructor is payable; its value is the keeper's messaging-fee money
(§3.12).

**Prologue (brick zone).** The constructor:

- reads `context()` and decodes `Execution`;
- hashes the leaf and processes the proof;
- picks a branch.

None of this calls a library. A bad encoding or a bad proof only fails that
caller.

**Branches:**

| Caller | Condition                                                                                              | Action                                                                                                                                                                              |
| ------ | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| any    | proof invalid, or a leaf for another chain, or the default leaf (`chainId 0`) for anyone but the owner | revert `InvalidProof`                                                                                                                                                               |
| owner  | this chain's leaf and non-empty `routes[0]`                                                            | `ownerRoute`: liveness, the owner's own transaction                                                                                                                                 |
| owner  | otherwise (including the default leaf)                                                                 | `_refund`, no fee                                                                                                                                                                   |
| other  | no rules, or past `deadline`                                                                           | `_returnValue`, then `_refund`, fee to the caller                                                                                                                                   |
| other  | otherwise                                                                                              | `evaluate`; on a non-OK status `_returnValue`, then `_refund` (fee to the caller except on `UNBOUNDED`); on OK, sweep each caller-listed asset that isn't a rule input to the owner |

- **Beneficiary.** It is the owner. A zero owner is replaced by the caller and
  never matches the caller, so the owner arms stay unreachable.
- **Native.** It rides the `selfdestruct` to the beneficiary.
- **Returning the call value.** `_returnValue` sends `msg.value` back to the
  caller, tolerantly. If that send fails, the value rides the `selfdestruct` to
  the beneficiary.
- **Refund (brick zone, tolerant).** The refund:
  1. pays each `refunds` entry's fee in kind, best-effort, unless the caller is
     the owner or the status is `UNBOUNDED`;
  2. sweeps that entry's asset;
  3. sweeps every rule input, fee-free;
  4. sweeps the caller's list.

  All transfers are raw calls that tolerate failure. Malformed indices are
  skipped. For a token entry, `_tryPay` sends `held − fee` to the owner first
  and pays the fee only when that transfer succeeded, or when nothing is left
  beyond the fee. An owner a token blocks therefore never pays out a fee on
  every call. Native needs no such order: the rest rides the `selfdestruct`.

- **Default leaf.** It makes deposits recoverable by the owner on any chain the
  tree doesn't cover. A tree without one leaves such deposits unrecoverable
  (§9.2).

---

## 5. IntentRouter

The constructor takes the chain's `EphemeralFactory`, stored as an immutable.

`executeIntent(intent, signature, router, routes, contexts)` is payable. It runs
these steps:

1. `lock.enter()`: the shared intent lock, held by the factory (§4).
2. Keeper gate, `chainId == block.chainid`, then `start` and `deadline`.
3. Signature over the EIP-712 digest under `IntentRouter`/`2`: ECDSA first (EOAs
   and EIP-7702 accounts), then ERC-1271. The intent stays in calldata
   throughout: the router keeps no memory copy of it.
4. A `STANDING` intent with neither interval nor count is rejected `MALFORMED`
   if any rule has inputs or fees. Otherwise a keeper could repeat it in one
   block until the allowance runs out.
5. The record is written (`Exhausted`, `NotYet`).
6. `evaluate` runs with `holder = owner`, `pull = true` and `value = msg.value`.
   A non-OK status reverts `Rejected(status)`.
7. `lock.exit()`.
8. Any native balance left goes back to `msg.sender`.

Tokens move only from the owner:

- fees, which are `transferFrom` straight to the keeper;
- input pulls into the router, for exactly the consumed amount less the fee;
- direct handoff pulls.

During the transaction the router holds the pulled inputs and approves the
EnsoRouter for exactly those amounts.

- **Router choice.** The EnsoRouter is the committed `constraints.router`, or
  the keeper's `router` argument when none is committed.
- **Handoff after a route.** It takes the router's own balance, so the route
  must deliver back to `IntentRouter`.
- **Native.** Native inputs and native fees revert `UnsupportedAsset`. Native
  outcomes are supported.
- **Shared records.** Intents an owner signs with the same nonce share a record,
  so they form one cancellation group. `cancel(nonces)` marks each one terminal,
  including nonces that haven't been used yet.

---

## 6. Guardians

**Interface.**

- `accept(intentHash, owner, keeper, token, amount, obligation, context)`,
  payable. It takes the asset from the caller against the obligation and returns
  a receipt.
- `Accepted(receipt indexed, intentHash indexed, caller indexed, owner, keeper, amount, obligation)`.
- `level()` is FORWARD, BONDED or FRONTED. Only FORWARD exists.
- Anyone may call `accept`. A record counts only when `caller` is the intent
  address or the router of `intentHash`.
- `owner` is authenticated only when the caller is the IntentRouter. An intent
  address's owner is a field of a leaf anyone can build. A guardian that acts on
  the owner's account must accept calls from the IntentRouter alone.

**`BridgeGuardian`** is FORWARD over CCTP V2 and Across.

- **Structure.** It is non-upgradeable, has no admin, and its per-chain
  configuration is fixed at construction. Nothing rests in it.
- **Call value.** It charges no native fee and reverts `UnexpectedValue` for any
  call value.
- **Context.** `abi.encode(uint256 value, bytes32 method, bytes params)`.
  `value` is always 0 here and is ignored. A committed method must match;
  otherwise the keeper chooses.
- **Receipts.** A receipt is the running count of acceptances, so `accept`
  writes no slot per receipt. `status` answers `PENDING` for 1 to the count and
  `NONE` otherwise. A receipt is unique per guardian only.
- **Zero amounts.** `amount == 0` reverts `ZeroAmount`, after the method's own
  checks.
- **CCTP.**
  - Params are `(uint256 maxFee, uint32 minFinalityThreshold, Subsidy subsidy)`.
  - The input must be the local USDC.
  - The destination must be in the table, and the delivered token must be that
    destination's native USDC.
  - The burn is the handed amount plus any subsidy fee. The burn less `maxFee`
    must be at least `minAmount`.
  - `destinationCaller` is 0, so anyone may relay the attestation.
  - CCTP has no refund path and no depositor-signed amendment, so the CCTP leg
    has no counterpart to Across's refund checks.
- **Across routes.** Routes are a constructor table keyed by
  `keccak256(abi.encode(input, chainId, output))`. Each holds a `(mul, div)`
  scale for the decimals gap. An unknown key reverts `UnsupportedRoute`.
- **Across.**
  - Params are `(uint256 outputAmount, uint32 fillDeadline, Subsidy subsidy)`.
  - The depositor (who receives Across refunds) is `obligation.refund`. It must
    be non-zero and must not be the caller (`RefundToCaller`), because a refund
    to the intent address would trigger the rule again.
  - The depositor must be the owner passed to `accept` (`RefundNotOwner`). The
    SpokePool's `speedUpDeposit` lets the depositor sign a lower output and a
    new recipient, which relayers may fill against, so whoever holds the
    depositor role controls the delivery.
  - `minAmount` counts in input units, as for CCTP. The declared `outputAmount`
    is scaled into input units, then it must be at least `minAmount`
    (`BelowMinimum`) and must not exceed the deposit, the handed amount plus any
    subsidy fee (`AboveInput`).
  - `fillDeadline` must not be after the obligation's deadline
    (`DeadlineTooLate`), and must be at least 30 minutes ahead
    (`DeadlineTooEarly`).
  - Every deposit names no exclusive relayer and no exclusivity, so any relayer
    may fill it from the first block.
  - **The band.** The keeper chooses `outputAmount` between the floor and the
    deposit. The difference goes to whichever relayer fills it. A keeper that
    also relays competes for it with every other relayer.
- **Subsidies.** A subsidy `(payer, fee, nonce, deadline, signature)` lets
  someone other than the owner pay the bridge's fee (the Across relayer, or
  Circle's fast-transfer fee), so a template can set the floor to the consumed
  amount and still be delivered (1:1 delivery).
  - A zero fee pays nothing and the other fields are ignored.
  - Otherwise the guardian pulls `fee` of the input token from `payer` through
    Permit2's `permitWitnessTransferFrom`, at the canonical Permit2 address, and
    deposits or burns `amount + fee`.
  - The witness is the bridge call, with `caller = msg.sender`:
    - Across:
      `Deposit(caller, intentHash, refund, recipient, chainId, output, amount, outputAmount, fillDeadline)`.
    - CCTP:
      `Burn(caller, intentHash, recipient, chainId, amount, maxFee, minFinalityThreshold)`.
      The delivered token is fixed by `chainId`.
  - `accept` is permissionless and its `intentHash` is the caller's claim, so
    the binding to `msg.sender` is what stops a copied signature being spent
    through another caller. The other fields tie the fee to this one call.
    Permit2 supplies the nonce and expiry.
  - The fee is pulled after the handed amount, and only after the method's
    checks have passed.
  - Whatever of the fee the bridge doesn't take goes to the user: Across refunds
    an unfilled deposit, fee included, to the depositor (the owner); CCTP mints
    the burn less the fee Circle actually charges to the recipient. The payer's
    leftover is lost to the user, which is the fail-safe direction.
  - `Subsidized(receipt, payer, fee)` follows `Accepted`.
- **Settlement.** `settle` reverts and receipts stay `PENDING`. FORWARD means
  delivery is the bridge's responsibility alone.

---

## 7. Deployment

`IntentDeployment` is the base for every deployer:

- It deploys through the canonical CREATE2 deployer (`0x4e59…956c`), calling it
  directly with `salt ‖ initCode`. On OP-stack forks, forge's salted `new`
  deploys from the sender instead.
- Deployment is skipped when code already exists at the predicted address. The
  script then requires code at that address.
- zkSync is refused, and so is any chain without the CREATE2 deployer.
- Forge deploys the linked libraries (`IntentEvaluator`, `IntentHash`) through
  the same deployer with salt 0. `_requireLinked` checks that each library's
  predicted address appears in the creation code and has code.

Addresses:

| Contract           | Salt                 | Address                                                              |
| ------------------ | -------------------- | -------------------------------------------------------------------- |
| `EphemeralFactory` | `"EphemeralFactory"` | the same on every chain                                              |
| `IntentRouter`     | `"IntentRouter"`     | the same on every chain                                              |
| `IntentCounter`    | `"IntentCounter"`    | the same on every chain                                              |
| `BridgeGuardian`   | `"BridgeGuardian"`   | per chain: the constructor arguments are this chain's `BridgeConfig` |

The router's init code includes the factory's predicted address, so the router's
address depends on the factory's. `IntentRouterDeployer` requires the factory to
be deployed first.

`BridgeConfig` holds the CCTP table (domain and native USDC), the Across
SpokePools, and the Across tokens by family: native USDC on the CCTP chains that
have a spoke pool (except Plasma), and USDT or USDT0. Each chain's guardian gets
a route from each local token to its family's token on every other listed chain.
Other Across assets (WETH, ETH, WBTC) have no routes and are refused. Before
deploying, `_checkLocal` checks on-chain:

- the messenger's local domain;
- a non-zero burn limit for USDC;
- the SpokePool's `chainId`;
- each local Across token's `decimals()` against the table.

After deploying, the deployer reads every route back from the guardian.

`IntentDeploymentsWriter` forks every `rpc_endpoints` entry. It lists each chain
where the factory is deployed, and writes `deployments.json` into the intent
SDK.

Because CREATE2 commits to the init code, code at a predicted address is this
build's code. The executor's creation code also fixes every intent address,
because the address is derived from the executor's init code. Any change to the
executor or the evaluator changes these addresses, so it must land before
anything is funded.

---

## 8. Decisions on record (not findings)

- **Static refusals refund at once, open to anyone, fee paid.** `MALFORMED`,
  `UNSUPPORTED` and `CUSTODIAL` come before the keeper gate. Such a leaf can
  never run, so its funds go back immediately.
- **`EXHAUSTED` refunds with fee.** It comes after the keeper gate, so only an
  eligible caller triggers it. After a `ONCE` executes, a later deposit is
  refunded rather than stranded.
- **`UNBOUNDED` refunds without the fee.** The refusal depends on what is at the
  address, which a caller can steer with a deposit.
- **The owner is an authority**, as in the v2 note's §2: they can refund or
  re-route at any block, and the keeper's only commitment point is inclusion.
  Owner routes are unvalidated.
- **`ROUTE_NONE` ignores keeper bytes.** Such rules move funds only to fees and
  committed handoffs.
- **A handoff after a route takes the whole balance** of the handed asset at the
  executing contract. That can include any part of an `EXACT` input not
  consumed, or other deposits of that asset. The recipient is committed. Under
  `FRAME_STRICT`, a named asset dropping beyond what is permitted reverts.
- **The keeper's messaging-fee value never reaches the owner.** It is either
  forwarded to guardians in full or returned to the caller (§3.12).
- **Every term an active rule references must be computable before execution**
  (§3.4). A reverting view or a division by zero in any group of an active rule
  fails the execution. This is liveness only.
- **Counter windows are aligned to the epoch; lifetime windows to `start`.**
- **`record()`'s return value is unused.** The verdict is read earlier in the
  same call. Only the executor can write its own entry. A root executes at most
  once per transaction: the lock prevents a nested execution, and the executor's
  address keeps its nonce until the end of the transaction (EIP-6780), so a
  second, sequential `CREATE2` of the same root collides and reverts.
- **`DRAIN` on the router path pulls the owner's whole wallet balance** of the
  asset and never reads the allowance. A short allowance reverts the pull, which
  is liveness only. The owner signs the `DRAIN` code.
- **A zero `keeper` means anyone may execute.** The outcome bounds are then the
  owner's only protection. The SDK lints `keeper-zero`.

---

## 9. Where we want attention

1. **Brick-zone gas.** The prologue decodes and hashes the whole leaf, and
   `_refund` walks the refund list and every rule's inputs. An intent large
   enough to exceed the block gas limit on those paths could never be refunded.
   Nothing on-chain bounds its size.
2. **Uncovered chains.** Without a default leaf, a deposit on a chain the tree
   doesn't cover reverts `InvalidProof` for everyone, owner included. The SDK
   template's `default` is optional today.
3. **The custody test is structural.** It accepts any post-state lower bound
   with a positive pre-state floor. That includes bounds on a third party's
   balance, or on a view the keeper's route can move. What the bound measures is
   the SDK lint's job. Review whether the test lets a keeper route through with
   a bound that protects nothing.
4. **Inflows a route triggers.** A `DELTA` outcome bound is the account's net
   change over the execution, so it can't tell who paid. A keeper route can
   trigger a payment the account is already owed, on either carrier: completing
   a pending CCTP mint or an Across fill to the account, or any payout owed to
   it. The lock (§4) removes the case of running another intent inside the
   route. Under the router, a `DELTA` bound reads the owner's whole account. The
   mitigation is an SDK lint rejecting a `DELTA`/`POST_VIEW` bound on an account
   an outside party can credit (§11).
5. **Steering a refund.** A caller who can move a pre-state input to the floor
   (a `PRE_VIEW` of a pool, a spot oracle) can make the runtime custody test
   fail. The result is `UNBOUNDED`, which pays no fee but still refunds: the
   owner's cost is a fresh deposit. The same holds for a deposit that makes a
   keeper-routed rule's bound non-positive.
6. **The freeze step and memoization.**
   - `_freeze` must compute exactly what later steps read: the fee candidate it
     primes must be the one `_payFees` picks.
   - Scoped memos must stay per rule.
   - No post-state term may be cached before the post phase.
7. **Approvals.**
   - ERC20: `forceApprove` the exact amount, then revoke.
   - ERC721: approve the one token id, and revoke only if it is still held.
   - ERC1155: approval for all only with a committed router.
   - The frame's ERC20 approval check.
   - Whether any route shape can leave an approval in place that outlives the
     holder.
8. **The messaging-fee reserve.** The keeper's value must never be spent as the
   owner's, and the owner's must never be returned as the keeper's. Check every
   native read in the evaluator, the executor's `_returnValue` ordering, and the
   reset on the `UNBOUNDED` path.
9. **Context first word.** Every guardian receives contexts whose first word the
   evaluator has already read as the fee. A guardian that decodes the context
   differently would misread its parameters.
10. **Lock ownership.** The holder model assumes no route can make the factory
    or the router call `exit()` on its behalf.
11. **Factory transient context.** The chunked `tstore`/`tload`, the
    canonical-offset check, and handing the executor the caller's raw encoding
    to decode.
12. **EIP-712.** The type strings, the alphabetical order of referenced types,
    and nested arrays of structs and bytes. `hash.t.sol` pins a digest and a
    leaf produced by viem for an intent that populates every field.
13. **`IntentRecord` arithmetic.** Window anchoring, the terminal check order,
    and that `start ≤ now` is enforced before `block.timestamp - start`.
14. **`BridgeGuardian` parameters the keeper controls.** CCTP `maxFee` and
    finality; Across `outputAmount` and `fillDeadline`; the subsidy on either.
    None should let the keeper deliver below `minAmount`, change the recipient,
    or redirect a refund. A subsidy should never let anyone spend a payer's fee
    on a bridge call the payer didn't sign for.
15. **Lint suppressions.** Each `forge-lint` disable states its reason. The
    evaluator disables `calls-loop` and `require-revert-in-loop` library-wide:
    every loop runs over committed lists, and any revert aborts the whole
    execution. Check that each reason holds.

---

## 10. Tests

Unit tests:

- **`test/unit/concrete/wallet/ephemeralIntentExecutor/`:**
  - `route.t.sol`: keeper and committed routes, floor, `EXACT`, the exclusivity
    handover, address reuse.
  - `constrained.t.sol`: every `UNSUPPORTED`, `CUSTODIAL` and `UNBOUNDED`
    refusal, statically and at runtime; a routed rule without inputs; a
    post-state comparison beside a bound.
  - `pair.t.sol`: thresholds, matching, fee candidates.
  - `terms.t.sol`: oracle value floor, staleness, post-view floor, counters, and
    a pre-state view fixed before a committed route.
  - `handoff.t.sol`: amount, context, level, `EXACT`, a handoff minimum fixed
    before a keeper route, and messaging fees: the fee forwarded from the
    context word, the owner's native never forwarded, unspent value reverting,
    and the value returned to the caller on refund.
  - `lifetime.t.sol`: once, scheduled, counted, unrecorded standing.
  - `owner.t.sol`: owner refund and route; a zero owner gets no owner arms.
  - `refund.t.sol`: deadline refunds, refund-only chains, the default leaf,
    proofs, two-chain trees.
- **`test/unit/fuzz/wallet/ephemeralIntentExecutor/refundNeverReverts.t.sol`:**
  the refund arm never reverts for fuzzed inputs and sweep lists, and a bad
  proof only ever reverts `InvalidProof`.
- **`test/unit/concrete/factory/ephemeralFactory/`:** domain, init code,
  canonical encoding, empty context outside a construction, reentry, only the
  lock's holder releasing it, records keyed by writer, address derivation.
- **`test/unit/concrete/router/intentRouter/`:** `EXACT` and `DRAIN` pulls,
  lifetimes, the standing-unbounded rejection (inputs or fees), attestation and
  custody refusals, signatures, window and chain, keeper exclusivity, handoff
  with fee value, unspent call value reverting, a route that executes an intent
  address reverting `Locked`, cancel, and the golden-vector `hash`.
- **`test/unit/concrete/intent/bridgeGuardian/`:** every CCTP and Across check
  against mocks, including the route table, an unlisted route, input-unit
  scaling, `AboveInput`, `DeadlineTooEarly`, `RefundNotOwner`, no exclusive
  relayer, `ZeroAmount`, `UnexpectedValue`, the `Accepted` fields and receipts
  counting up. Subsidies run against Permit2 etched at its canonical address.
  For Across: a 1:1 deposit topped up by the fee, a signature for another caller
  or another deposit (`InvalidSigner`), a replayed nonce, and `AboveInput`
  against the handed amount plus the fee. For CCTP: a burn topped up to cover
  `maxFee`, a fee short of it (`BelowMinimum`), and a signature for another
  caller, a higher `maxFee` or another recipient (`InvalidSigner`).
  `test/utils/Subsidies.sol` signs them. Also `uda.t.sol`, a deposit-address
  template end to end (USDC via CCTP, USDT via Across, both in one execution,
  and a subsidized 1:1 Across leg whose payer signs for the intent address and
  the intent's id). On that template it also covers two rules naming one handoff
  or comparing one balance change (`MALFORMED`), a handoff minimum of zero, and
  the refund order against an owner the token blocks (`MockBlockingERC20`, a
  token with a blocklist as USDC and USDT have).

Forge runs each top-level test call as its own transaction here, so transient
storage doesn't persist between calls in a test. The lock test runs its sequence
inside one call.

Fork tests:

- **`test/fork/intent/BridgeGuardian.t.sol`** deploys the guardian with its own
  deployer on Base and Ethereum forks. It runs `accept` against the live
  TokenMessengerV2 and SpokePools, and asserts the emitted `DepositForBurn` /
  `FundsDeposited`, the burn or escrow, and that nothing is left in the
  guardian. A subsidized USDT deposit on Ethereum and a subsidized fast CCTP
  burn on Base run through the live Permit2. This covers the source chain only.

Off-chain, the intent SDK's suite runs the deployed `IntentEvaluator.check`
against the SDK's port, and compares `IntentRouter.hash` and
`EphemeralFactory.getAddress` with the SDK's own derivations. It also signs a
subsidy for each method with the SDK's typed data and has `BridgeGuardian`
accept it through Permit2.

---

## 11. Open items

- **SDK controls behind §9.1–9.4:** a bound on leaf size, a required default
  leaf, lint rules on what custody bounds measure, and a lint rejecting
  `DELTA`/`POST_VIEW` bounds on accounts an outside party can credit.
- **SDK interface.** The SDK must follow the current `Accepted` ABI and topic,
  the context's leading value word, the CCTP and Across params with their
  subsidy, Across minimums in input units, and the router and factory addresses.
- **`IntentDeploymentsWriter`** doesn't yet write the Across route list to
  `deployments.json`.
- **Arc.** The Arc USDC row's `decimals()` is not confirmed on-chain.
- **Tempo.** Deployment there is untested: anvil cannot estimate gas on a fork.
  Dry-run against the live RPC first.
- **Codecs.** The backend and alpha-scanners codecs must move to this format
  before anything is funded or signed.
- **Source comments to correct:**
  - `IIntentRouter.sol` and `IntentEvaluator.sol` say keeper bytes serve "rules
    without a committed route"; they serve `ROUTE_KEEPER` rules only.
  - The executor's sweep comment says unconsumed tokens "always go back to the
    owner"; only the caller's sweep list does.
  - `IIntent.sol` states field rules that `check` doesn't enforce: `request`
    only under `ROUTE_KEEPER`, a handoff `refund` that is never the intent
    address, and `Asset.chainId == Handoff.chainId`.

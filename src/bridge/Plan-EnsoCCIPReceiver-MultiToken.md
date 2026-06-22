# Enable MultiToken on EnsoCCIPReceiver (V2)

## Goal

Support CCIP messages that deliver **up to 2 different ERC-20 tokens**, routing
them through `EnsoRouter.routeMulti` (2 tokens) or `EnsoRouter.routeSingle` (1
token), while preserving the existing defensive "never revert in `_ccipReceive`"
design.

## Resolved decisions

- **New contract, V1 untouched.** Create `EnsoCCIPReceiverV2` +
  `IEnsoCCIPReceiverV2` (new interface), new deployer, tests, and docs.
  `EnsoCCIPReceiver` 1.0.0 stays exactly as it is.
  `typeAndVersion = "EnsoCCIPReceiver 2.0.0"`.
- **Token representation: dynamic arrays capped at 2.** Use `address[]` /
  `uint256[]` sourced from `_message.destTokenAmounts`, validated to
  `length ∈ {1, 2}` via a `MAX_TOKENS = 2` constant. This matches
  `EnsoRouter.routeMulti`'s `Token[]` input and lets us raise the cap later with
  minimal change.
- **Malformed multi-token → quarantine, never revert.** No new revert paths in
  `_ccipReceive`. Bad shapes (duplicate tokens, zero amount in a slot, too many
  tokens, bad payload) escrow funds in-place via a new/extended `ErrorCode`,
  consistent with V1.

## Key data-model clarification

In V1, `token`/`amount` come from `_message.destTokenAmounts` (what CCIP
actually delivered), and `_message.data` carries only
`(receiver, shortcutData)`. **V2 keeps this model**: the token set is the
authoritative CCIP-delivered `destTokenAmounts`, not something re-declared in
the payload.

Consequences:

- The `CCIPMessageDecoder` library is **unchanged** — payload is still
  `abi.encode(address receiver, bytes shortcutData)`. One receiver, one
  shortcut, N input tokens. No per-token data needed in the payload.
- Because `tokens` and `amounts` both come from `destTokenAmounts` (each
  `Client.EVMTokenAmount` pairs token+amount), they are **always equal length**.
  The "tokens.length == amounts.length" check from the notes is therefore
  **unnecessary** and no error code is added for it.

---

## Files

### New

- `src/bridge/EnsoCCIPReceiverV2.sol`
- `src/interfaces/IEnsoCCIPReceiverV2.sol`
- `script/EnsoCCIPReceiverV2Deployer.s.sol`
- `src/bridge/EnsoCCIPReceiverV2.md` (mirror of `EnsoCCIPReceiver.md`)
- `test/unit/concrete/bridge/ensoCCIPReceiverV2/` — one `*.t.sol` per function +
  `.tree` (mirror the existing `ensoCCIPReceiver/` layout: `acceptOwnership`,
  `ccipReceive`, `constructor`, `execute`, `getEnsoRouter`, `pause`,
  `recoverTokens`, `renounceOwnership`, `supportsInterface`,
  `transferOwnership`, `typeAndVersion`, `unpause`, `wasMessageExecuted`).

### Reused unchanged

- `src/libraries/CCIPMessageDecoder.sol` (payload shape is identical).

---

## Contract design (`EnsoCCIPReceiverV2`)

### Constant

```solidity
uint256 private constant MAX_TOKENS = 2;
```

### `_validateMessage` → returns arrays

Signature changes from singular to arrays:

```solidity
returns (
    address[] memory tokens,
    uint256[] memory amounts,
    address receiver,
    bytes memory shortcutData,
    ErrorCode errorCode,
    bytes memory errorData
)
```

Validation order (first failure wins):

1. Replay (`s_executedMessage[messageId]`) → `ALREADY_EXECUTED`
2. `destTokenAmounts.length == 0` → `NO_TOKENS`
3. `destTokenAmounts.length > MAX_TOKENS` → `TOO_MANY_TOKENS`
4. Build `tokens`/`amounts` from `destTokenAmounts`; if **any**
   `amounts[i] == 0` → `NO_TOKEN_AMOUNT` (encode offending index in `errorData`)
5. `length == 2 && tokens[0] == tokens[1]` → `DUPLICATE_TOKENS` _(new)_
6. `_tryDecodeMessageData` fails → `MALFORMED_MESSAGE_DATA`
7. `receiver == address(0)` → `ZERO_ADDRESS_RECEIVER`
8. `paused()` → `PAUSED`
9. else → `NO_ERROR`

### `_ccipReceive`

Same control flow as V1, but operating on arrays:

- `NONE` (ALREADY_EXECUTED) → idempotent return.
- `TO_RECEIVER` (PAUSED) → mark executed,
  `_refundAll(tokens, amounts, receiver)`.
- `TO_ESCROW` (all malformed cases) → mark executed, emit
  `MessageQuarantined(... tokens, amounts ...)`, funds stay.
- `NO_ERROR` → mark executed, `try this.execute(tokens, amounts, shortcutData)`;
  on revert emit `ShortcutExecutionFailed` and
  `_refundAll(tokens, amounts, receiver)`.

### `execute` (self-call) → explicit length branches, fail closed

Match the exact supported shapes (`MIN_TOKENS == 1` → `routeSingle`,
`MAX_TOKENS == 2` → `routeMulti`) and revert on anything else. The cap is frozen
per deployment (a higher cap ships as a new contract), so pinning the branches
to the constants is correct and self-documenting; the revert is defensive
(unreachable in normal flow since `_validateMessage` already gates the length).

```solidity
function execute(address[] calldata tokens, uint256[] calldata amounts, bytes calldata shortcutData) external {
    if (msg.sender != address(this)) revert EnsoCCIPReceiverV2_OnlySelf();
    uint256 length = tokens.length;
    if (length == MIN_TOKENS) {
        Token memory tokenIn = Token({ tokenType: TokenType.ERC20, data: abi.encode(tokens[0], amounts[0]) });
        IERC20(tokens[0]).forceApprove(address(i_ensoRouter), amounts[0]);
        i_ensoRouter.routeSingle(tokenIn, shortcutData);
        return;
    }
    if (length == MAX_TOKENS) {
        Token[] memory tokensIn = new Token[](length);
        for (uint256 i; i < length; ++i) {
            tokensIn[i] = Token({ tokenType: TokenType.ERC20, data: abi.encode(tokens[i], amounts[i]) });
            IERC20(tokens[i]).forceApprove(address(i_ensoRouter), amounts[i]);
        }
        i_ensoRouter.routeMulti(tokensIn, shortcutData);
        return;
    }
    revert EnsoCCIPReceiverV2_UnsupportedTokensLength(length);
}
```

### `_refundAll` helper (private)

```solidity
function _refundAll(address[] memory tokens, uint256[] memory amounts, address to) private {
    for (uint256 i; i < tokens.length; ++i) {
        IERC20(tokens[i]).safeTransfer(to, amounts[i]);
    }
}
```

### Unchanged surface

`pause` / `unpause` / `recoverTokens` (stays single-token; owner calls per
token) / `getEnsoRouter` / `wasMessageExecuted` / `_getRefundPolicy` (add
`DUPLICATE_TOKENS → TO_ESCROW`).

---

## Interface (`IEnsoCCIPReceiverV2`)

- **`ErrorCode`** — **append** `DUPLICATE_TOKENS` as value `8`. Values `0–7`
  stay byte-for-byte identical to V1 so existing decoders/indexers/dashboards
  interpret the emitted `uint8` the same across versions; only the new value
  needs adding. Do NOT insert it in the middle (that would shift
  `MALFORMED_MESSAGE_DATA`/`ZERO_ADDRESS_RECEIVER`/`PAUSED`).
  ```
  NO_ERROR, ALREADY_EXECUTED, NO_TOKENS, TOO_MANY_TOKENS, NO_TOKEN_AMOUNT,
  MALFORMED_MESSAGE_DATA, ZERO_ADDRESS_RECEIVER, PAUSED, DUPLICATE_TOKENS
  ```
- **`MessageQuarantined`** — change to arrays:
  ```solidity
  event MessageQuarantined(
      bytes32 indexed messageId, ErrorCode indexed code,
      address[] tokens, uint256[] amounts, address receiver
  );
  ```
- **`execute`** — new signature
  `execute(address[] tokens, uint256[] amounts, bytes shortcutData)`.
- **Errors** — rename to `EnsoCCIPReceiverV2_*` (OnlySelf, UnsupportedErrorCode,
  UnsupportedRefundKind).
- `ShortcutExecutionSuccessful` / `ShortcutExecutionFailed` / `TokensRecovered`
  / `MessageValidationFailed` / `RefundKind` unchanged.

---

## Deployment script (`EnsoCCIPReceiverV2Deployer.s.sol`)

- Copy `EnsoCCIPReceiverDeployer.s.sol`; reuse the **same** 25-chain CCIP/Enso
  router table (only the deployed contract type changes).
- Use a distinct CREATE2 salt: `salt: "EnsoCCIPReceiverV2"`.
- Keep the same env (`PRIVATE_KEY`), owner-is-deployer, and zero-address guards.

---

## Tests (BTT)

Mirror `EnsoCCIPReceiver.tree` and add/modify branches:

- `CcipReceive`: the existing "more than one token → TOO_MANY_TOKENS" branch now
  means **> 2 tokens** (e.g. length 3). Add:
  - `when message has two tokens` →
    - `when tokens are duplicated` → MessageValidationFailed +
      MessageQuarantined + escrow both.
    - `when a token amount is zero` → NO_TOKEN_AMOUNT + quarantine.
    - `when well-formed` → success path runs `routeMulti`; assert both tokens
      consumed and shortcut outputs delivered.
    - `when shortcut execution failed (2 tokens)` → both tokens refunded to
      receiver (loop).
    - `when paused (2 tokens)` → both tokens refunded to receiver.
- `Execute`: add `when one token → routeSingle` and
  `when two tokens → routeMulti` cases.
- Update `MessageQuarantined` assertions for the array signature throughout.
- `SupportsInterface`, `Constructor`, ownership, pause, `recoverTokens`, views:
  copy as-is.
- Setup already mints `s_tokenA` and `s_tokenB` — reuse for the 2-token
  shortcut. A new multi-input shortcut fixture in
  `test/shortcuts/ShortcutsEthereum.sol` may be needed for the happy-path
  `routeMulti` assertion.
- Regenerate trees with `bulloak` (existing workflow) and keep `forge fmt` /
  lint clean.

---

## Verification / open items (do before deploy)

- **Infra alignment.** Confirm infra builds the CCIP send with both tokens in
  `tokenAmounts` (not in the data payload) and keeps
  `data = abi.encode(receiver, shortcutData)`.
- **Tooling.** Consider a small skill/command to scaffold the V2 BTT trees +
  per-function test files from V1 (the notes flagged this; out of scope for the
  contract change itself).

## Implementation checklist

1. `IEnsoCCIPReceiverV2.sol` (enum + array event + new `execute` sig + errors).
2. `EnsoCCIPReceiverV2.sol` (`MAX_TOKENS`, array `_validateMessage`, `execute`
   branch, `_refundAll`, `DUPLICATE_TOKENS` policy, `typeAndVersion` 2.0.0).
3. `EnsoCCIPReceiverV2Deployer.s.sol` (router table + new salt).
4. Tests: trees + per-function `*.t.sol` under `ensoCCIPReceiverV2/`,
   multi-input shortcut fixture.
5. `EnsoCCIPReceiverV2.md` docs.
6. `forge build` + `forge test` + `forge fmt` + lint.
7. Resolve verification items above.

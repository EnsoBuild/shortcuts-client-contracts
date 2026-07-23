<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Router and shared shortcut wallet

Core files: `EnsoRouter.sol`, `EnsoShortcuts.sol`, `IEnsoRouter.sol`.

## Flow

- `EnsoRouter` constructs one dedicated `EnsoShortcuts(address(this))`; only
  that router may execute its Weiroll programs.
- `routeSingle`/`routeMulti` pull ERC-20/721/1155 inputs from `msg.sender`
  directly into the shared shortcuts wallet, then call arbitrary encoded
  shortcut calldata on it. Native value is already held by that wallet during
  execution.
- Public callers choose tokens, amounts, receiver, and program. The security
  boundary is atomic funding plus complete cleanup — not caller or target
  allowlisting.
- Router's low-level call bubbles the shortcuts contract's revert data. A target
  failure inside Weiroll has already been wrapped by the VM. Any pull or program
  failure rolls the transaction back.

## Safe routes

- `safeRouteSingle`/`safeRouteMulti` snapshot the receiver's requested output
  balances and require each post-execution delta to meet `minAmountsOut`.
- This protects only those receiver/token deltas. It does not prove route
  quality, validate intermediate calls, or prevent unrelated shared-wallet
  residue.
- ERC-721 output checks count the receiver's NFTs rather than proving ownership
  of a particular ID; ERC-1155 checks the specified ID.
- Duplicate native inputs are rejected; `msg.value` without a native descriptor
  is rejected. When native is present, its encoded amount is not matched to
  `msg.value`: all value is used.

## Shared-wallet invariants

- End every successful route with no user funds or exploitable approvals on
  `EnsoShortcuts`. Because the router is public and commands are arbitrary, a
  later caller can target residue.
- Plain routes make no output/refund guarantee; even empty/raw calldata can
  reach the wallet's receive path after inputs were transferred. Safe routes add
  only declared balance deltas.
- Fee-on-transfer inputs can deliver less than the encoded amount because the
  router does not assert the wallet's received delta.
- Do not make the shared shortcuts address a user receiver or durable spender.
  Builder deliberately rejects those patterns.
- Approvals should be exact/short-lived where possible and consumed or revoked.
  Review helpers and protocol calls that leave residual approvals independently.
- Router/shortcuts are a pair: the shortcuts address is created with ordinary
  `CREATE` inside the router constructor and must be read from
  `router.shortcuts()`, not derived from a separate CREATE2 salt.

## Cross-repo contract

- Builder's router client supplies input approvals to the router, selects safe
  routes when minimum outputs exist, and encodes `executeShortcut` for
  `router.shortcuts()`.
- Address changes must update `shortcuts-builder/src/client/addresses.ts`;
  backend imports those getters. Verify both router code and its `shortcuts()`
  child live.
- A client-side “single call” optimization can bypass Weiroll and change the
  effective wallet; review builder behavior when relying on `walletAddress()`
  substitutions.

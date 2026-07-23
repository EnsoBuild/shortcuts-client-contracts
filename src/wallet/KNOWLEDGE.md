<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Wallets, delegates, factories, and account abstraction

Core files: `wallet/EnsoWalletV2.sol`,
`delegate/{EnsoReceiver,DelegateEnsoShortcuts,EIP7702EnsoShortcuts}.sol`,
`factory/`, `paymaster/SignaturePaymaster.sol`, `utils/Withdrawable.sol`.

## EnsoWalletV2

- Non-upgradeable minimal clone. The implementation disables initializers in its
  constructor; clone initialization records fixed owner/factory and initially
  authorizes both as shortcut/multisend executors.
- Executors may run Weiroll and multisend. Only owner may make arbitrary
  `execute` calls or recover assets. Owner or factory may add/revoke executors;
  owner and factory cannot rotate.
- `EnsoWalletV2Factory.deploy(account)` is public/idempotent: anyone may
  materialize the deterministic wallet, but initialization gives them no
  control.
- `deployAndExecute` always uses `msg.sender`'s wallet. It atomically
  deploys/reuses, transfers assets, grants requested executors, calls wallet
  calldata as the factory, then optionally revokes those executors.
- Revocation does not distinguish newly granted from pre-existing authorization.
  Never include a permanent executor in a grant-and-revoke list; backend queries
  adapter authorization before adding it.
- Native descriptors carry no authoritative amount: at most one is allowed, and
  all `msg.value` funds the wallet call. No native descriptor requires zero
  value.

## EnsoReceiver (ERC-4337 checkout account)

- Deterministic clone with fixed owner and mutable `signer`/`entryPoint`; zero
  values are not rejected. Owner can shortcut, multisend, and recover. The
  configured EntryPoint reaches execution through `safeExecute`.
- `safeExecute` self-calls arbitrary account calldata. Success returns normally;
  failure is intentionally swallowed and exactly the caller-declared
  native/ERC-20 amount is refunded to owner. Refund failure reverts. There is no
  output or balance assertion.
- Only owner or self may enter shortcut/multisend; both use transient-storage
  reentrancy protection, so Cancun support is an operational dependency and
  nested self execution reverts.
- `validateUserOp` is EntryPoint-only. It first tries EIP-191 ECDSA over
  `userOpHash`, then ERC-1271 against the raw hash. Invalid signatures return
  ERC-4337's signature-failed value.
- EntryPoint supplies nonce/replay and the chain/EntryPoint signature domain.
  Receiver stores none, ignores `missingAccountFunds`, and rejects only nonce
  `type(uint64).max`; other ERC-4337 nonce keys/lanes remain valid despite the
  “unordered nonce” naming.
- Changing EntryPoint changes a major trust boundary and nonce domain: that
  address can invoke `safeExecute`.

## Determinism and initialization

- Wallet salt is `keccak256(abi.encode(account))`; Receiver salt is
  `keccak256(abi.encode(account, signer))`. Addresses also depend on factory,
  implementation, and proxy init-code hash.
- Receiver `deploy(account)` uses owner=signer;
  `delegateDeploy(account, signer)` separates refund owner from operation
  signer. Builder locally derives both forms, so factory/proxy formula changes
  are cross-repo changes.
- Clone deployment and initialization are atomic. Receiver's implementation is
  different: it does not disable initializers in a constructor, and deployment
  scripts brick it with a separate `initialize(0,0,0)` transaction. That gap is
  an initialization/front-run hazard for every new implementation deployment.
- `Withdrawable` always recovers native/ERC-20/ERC-721/ERC-1155 to `owner()`.

## Delegate and EIP-7702 surfaces

- `DelegateEnsoShortcuts` requires delegatecall by checking that execution
  address differs from immutable self. It has no caller role: the host
  (typically Safe) must authorize the delegatecall.
- `EIP7702EnsoShortcuts` is storage-free delegated EOA code requiring
  `msg.sender == address(this)`. Relayers cannot invoke it directly; EOA
  authorization/delegation lifecycle is external, and this contract is not
  itself an ERC-4337 account.

## SignaturePaymaster

- EntryPoint v0.7 is fixed at construction. Owner is `Ownable2Step`; owner
  manages an EOA signer allowlist, deposit withdrawals, and stake. Deposits are
  public. Renunciation can strand admin control.
- Packed data is paymaster + validation/postOp gas limits + `validUntil` +
  `validAfter` + ECDSA signature. Short input reverts during slicing.
- The signed EIP-191 digest commits to the material user-op fields, paymaster
  gas limits, validity window, chain ID, and paymaster address, while excluding
  the signature itself. EntryPoint enforces the returned time range.
- Any allowlisted backend signer can sponsor arbitrary otherwise valid user
  operations; the account signature remains separate authorization. There is no
  on-chain fee collection or post-op accounting, so failed shortcuts caught by
  Receiver can still consume sponsor funds.
- Receiver ignores missing prefund; production checkout therefore depends on
  paymaster sponsorship or an existing EntryPoint deposit.

## Cross-repo and tests

- Builder encodes `safeExecute` and deterministic init code; only the declared
  first input is automatically recoverable on checkout failure. Backend checkout
  assumes a sponsored, effectively single-input-sensitive path and lane-zero
  nonce.
- Wallet flashloan adapter must be an executor. Keep factory revocation behavior
  and backend executor checks aligned.
- Tests cover principal authorization, signatures, deterministic clones,
  refunds, multisend, recovery, paymaster roles/deposits, Safe delegation, and
  EIP-7702. Gaps worth preserving in review: receiver implementation race, zero
  roles, malformed paymaster data, missing prefund, general nonce lanes, and
  currently commented NFT factory cases.

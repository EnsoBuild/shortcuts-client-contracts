<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Shared execution semantics

Core files: `AbstractEnsoShortcuts.sol`, `AbstractMultiSend.sol`,
`EnsoShortcuts.sol`, and pinned `enso-weiroll`.

## Weiroll

- `AbstractEnsoShortcuts.executeShortcut` checks the surface-specific caller,
  executes `commands`/`state` through the Weiroll VM, and emits
  `ShortcutExecuted(accountId, requestId)`.
- Programs may perform `CALL`, `STATICCALL`, and value-bearing calls. They
  execute atomically; inner Weiroll commands do not support `DELEGATECALL`.
- Target failure is wrapped as the VM's
  `ExecutionFailed(commandIndex, target, message)`, not reliably bubbled
  verbatim. Only ordinary `Error(string)` is heuristically recovered; custom/raw
  revert data normally becomes `"Unknown"`.
- The _outer_ shortcut contract may itself run by delegatecall
  (`DelegateEnsoShortcuts`) or as delegated EIP-7702 code. In that case ordinary
  Weiroll calls operate from the host account and against host assets/storage
  context.
- `accountId` and `requestId` are not read for authorization or replay and are
  not stored. They are event metadata only.
- ABI packing, dynamic return references, tuple/array sentinels, and command
  flags are a shared contract with the planner in `enso-weiroll.js` and builder.
  VM/planner upgrades must be reviewed together.
- Static outputs must be one word. Dynamic output handling assumes the VM's
  supported single-return ABI shape; special command/output flags can use raw
  calldata/returndata or replace the whole state. Do not infer support for
  arbitrary Solidity return layouts.

## Multisend

- `AbstractMultiSend.multiSend` consumes Safe-style tightly packed transactions:
  operation byte, target, value, data length, data.
- Only `CALL` is accepted; a packed delegatecall operation reverts. Each failure
  bubbles revert data and rolls back the entire batch.
- Multisend has no independent nonce, replay protection, or identity semantics;
  the enclosing wallet/caller provides authority.

## Asset and value conventions

- The native sentinel is `0xEeee…`; several entry points treat the presence of a
  native token descriptor as a mode flag and use all `msg.value`, not the
  encoded native amount.
- The base shortcut contract accepts native, ERC-721, and ERC-1155 transfers.
  Acceptance is not a recovery policy: inspect the concrete surface for who can
  withdraw residue.
- Arbitrary-program safety depends on the surface:
  - router: public entry plus per-call funding into a shared singleton;
  - wallet/receiver: owner, executor, self-call, or EntryPoint authorization;
  - delegate/EIP-7702: host-account authorization;
  - bridge: messaging endpoint plus receiver policy;
  - solver/flashloan: immutable executor/callback boundaries.

## Change checklist

- If execution calldata changes, update builder ABI/selector encoders and every
  nested bridge/checkout wrapper.
- If command semantics change, test the pinned Solidity VM and TypeScript
  planner together.
- Test direct calls and intended delegated/self-call context separately;
  `address(this)`, `msg.sender`, token owner, and storage owner change across
  them.
- Include retained balances/allowances, unexpected `msg.value`, malformed packed
  input, and revert bubbling in review.

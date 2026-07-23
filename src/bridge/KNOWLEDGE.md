<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Bridge receivers

Core files: `LayerZeroReceiver.sol`, `EnsoCCIPReceiver.sol`,
`CCIPMessageDecoder.sol`. Both receivers turn externally authenticated bridge
delivery into an arbitrary router shortcut, so source authentication, replay
semantics, refund behavior, and retained funds are the review center.

## LayerZeroReceiver

- Entry requires the immutable LayerZero endpoint and a locally allowlisted
  `_from` OFT/pool. The receiver does not inspect decoded `srcEid`, `nonce`,
  `composeFrom`, executor, or extra data; remote-path trust rests on LayerZero
  plus the configured local OFT.
- Payload is `(receiver, nativeDrop, estimatedGas, shortcutData)`. The
  payload-chosen receiver is both output/refund destination and is not tied to
  `composeFrom`.
- ERC-20 OFT value is force-approved to the immutable Enso router; with native
  drop it routes multi-token. Native OFT amount is combined with all callback
  `msg.value`.
- `msg.value` may exceed `nativeDrop`; the full value is executed or refunded.
  `estimatedGas` is only a pre-call `gasleft()` floor, not a reservation.
- Shortcut failure is caught and original bridged assets/full native value are
  refunded. Malformed payload/codec, invalid pool token lookup, insufficient
  gas/value, or refund failure reverts the callback and leaves messaging-layer
  retry behavior in control.
- `messageExecuted[key]` is not a success ledger. Ordinary success/failure never
  writes it; only owner `sweep` writes an exact `(from,guid,message)` tombstone
  while recovering assets.
- Owner has immediate one-step ownership and arbitrary sweep; registrars manage
  OFTs. No pause exists. Constructor owner starts as registrar, and migration
  replaces the deployer registrar before ownership transfer.

## EnsoCCIPReceiver

- Chainlink's base contract gates calls to the immutable CCIP router.
  Application code does not validate `sourceChainSelector` or `sender`; there is
  no source-chain/sender allowlist.
- Exactly one nonzero ERC-20 is accepted. Valid data is ABI
  `(nonzero receiver, shortcutData)`; native and multi-token deliveries are
  unsupported.
- `messageId` is marked handled for execution, refund, or quarantine. Duplicates
  no-op. Uncaught transfer failure rolls back the mark and leaves delivery
  retryable.
- Shortcut execution is a catchable self-call. Shortcut failure refunds to
  decoded receiver and consumes the message.
- Pausing means refund-and-consume, not queueing. Malformed data, bad receiver,
  missing/multiple/zero token input are quarantined and consumed; owner may
  recover retained ERC-20s to any destination.
- Router addresses are immutable; owner is `Ownable2Step`, although renunciation
  is immediate. The decoder rejects truncation, misalignment, bounds errors, and
  trailing bytes, but accepts some aligned noncanonical encodings.

## Change and test checklist

- Treat protocol-router authentication and application source authorization as
  separate questions. Do not infer sender allowlisting from endpoint-only
  checks.
- Preserve the distinction between retryable reverts, caught/refunded failures,
  quarantine, and owner-created tombstones.
- Test refund transfer failure, malformed bridge messages,
  authorization/registrar changes, duplicate delivery, excess native value, and
  stranded approvals/balances.
- LayerZero coverage is fork-heavy and omits several
  authorization/malformed/replay branches. CCIP has detailed decoder coverage,
  but its duplicate-message test is skipped.
- Builder and backend own the matching callback encoders/datasets and LayerZero
  OFT registration. Payload or role changes must be reconciled there.
- Deployment router/endpoint selection, ownership, live OFT mappings, and
  two-step acceptance belong to
  [`script/KNOWLEDGE.md`](../../script/KNOWLEDGE.md).

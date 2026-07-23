<!-- verified-against: 51389b52ae365dac3c98d8e7c2f47321e5beffc4 -->

# Helpers

Helpers split into pure/view computation used while planning Weiroll state and
permissionless asset-moving helpers used as atomic execution waypoints. Do not
apply the safety assumptions of one group to the other.

## Asset-moving helpers

- **SwapHelpers:** caller chooses primary/operator/calldata/tokens/receiver and
  unchecked patch offsets. It forwards exact native input or pulls ERC-20, then
  sends its _entire_ output-token balance. `swapWithLimit` caps user output and
  sends excess to caller-chosen fee receiver; it is not a minimum-output check.
- **UniswapV4SwapHelpers:** fixed Universal Router/Permit2, but still transfers
  the helper's entire ERC-20 output balance. Native input checks presence rather
  than equality to `amountIn`; native output is not implemented. Amount/minimum
  narrow to `uint128`.
- **MaverickV2Helpers:** caller chooses manager/lens/receiver/refund, supplies
  two tokens, and receives a mint flow with all residual input balances swept to
  chosen refund address. No final minimum-LP assertion is added here.
- **SommelierHelpers:** requires `tx.origin == receiver`, explicitly coupling
  use to an origin EOA and excluding many relayer/smart-account paths.

These are public, caller-parameterized contracts. Never leave funds or useful
approvals on them: pre-existing balances can be included in a later caller's
whole-balance transfer. Review calldata patch bounds, allowance cleanup, native
equality, output-token type, and refund destination per integration.

## Computation and encoding gotchas

- `WeirollVerifier` signs only the personal-sign hash of `(commands,state)`: no
  chain, wallet/executor, account/request ID, nonce, or deadline domain. If
  integrated, signatures are replayable across those dimensions unless the
  enclosing system adds a domain. It is currently unused.
- `TupleHelpers` uses assembly/raw slices and trusts ABI shape, index, and type
  descriptors; it is not a safe decoder for adversarial malformed input.
- `MathHelpers`/`SignedMathHelpers.conditional` return fallback `a` when their
  internal staticcall fails, intentionally swallowing that failure.
- `BalancerHelpers` proportional BPT logic uses positive supplied amounts and
  assumes amount/balance index alignment.
- `ReserveHelpers` requires exact basket length, skips zero reserves, and takes
  the minimum ratio of the remainder.
- `HyperCoreHelpers` narrows token index and amount to `uint64`; make bounds
  explicit at callers.
- Uniswap conversion error names are not always type-accurate; do not build
  logic around revert text.

## Cross-repo and tests

- Helper ABI and numeric behavior are consumed by `shortcuts-standards`;
  deployed addresses are selected through builder/backend data. Change all sides
  together.
- Pure helper tests do not cover the custody properties of execution helpers.
  Add dust, pre-seeded balance, hostile receiver/operator, stale allowance,
  malformed offset, fee-on-transfer, excess/zero native value, and
  narrowing-boundary cases when touching asset-moving code.
- Helper deployment is CREATE2-driven. Verify the live address/code and consumer
  registry rather than assuming an unchanged salt means unchanged deployment.

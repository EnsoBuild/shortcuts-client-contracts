## Add {{CHAIN_NAME}} (`{{CHAIN_ID}}`) contract support

Issue: `{{TICKET}}`

### Agent-preparable work

- [ ] Add `{{CHAIN_ID}}` to the canonical chain ID library (ordered by chain
      ID).
- [ ] Inventory owner-dependent configuration; use `TODO_OWNER` with a
      `TODO({{TICKET}})` marker and leave it blocked until the approved address
      is supplied.
- [ ] Add the RPC variable to `.env.example`, the `[rpc_endpoints]` alias to
      `foundry.toml`, and the RPC secret to the CI workflow (alphabetical).
- [ ] Configure explorer verification behavior, or add the branch with a TODO
      when the explorer API is unconfirmed.
- [ ] Verify prerequisite contracts on-chain: CREATE2 factory, Multicall3,
      Permit2 (when in scope).
- [ ] Research flashloan, CCIP, and LayerZero candidates from official
      documentation and verified explorer pages.
- [ ] Prepare only the deployers approved for launch scope; make unsupported
      CCIP/LayerZero branches revert rather than fall through.
- [ ] Pre-compute expected CREATE2 addresses and compare with existing address
      families.
- [ ] Prepare deployment and verification commands; add tests only where the
      repository has a matching test surface.

### Human decisions and execution

- [ ] Approve the launch protocol and contract scope.
- [ ] Create or select the Safe multisig owner, or approve a hardware-wallet
      fallback when Safe is unavailable; final owner address: TBD
- [ ] Approve signer/threshold and custody configuration.
- [ ] Provide required RPC and explorer access through the team's approved
      process.
- [ ] Review and sign or approve actual deployment transactions.
- [ ] Commit or approve truthful broadcast artifacts produced by those
      transactions.
- [ ] Verify deployed contracts on the explorer.
- [ ] Confirm the configured owner and deployed contract state on-chain.

### Public evidence

- [ ] Chain documentation: TBD
- [ ] Prerequisite contracts (CREATE2 factory, Multicall3, Permit2) checked via
      RPC: TBD
- [ ] Expected CREATE2 addresses: TBD
- [ ] Deployment transactions: TBD
- [ ] Verified contract pages: TBD
- [ ] Flashloan provider deployment pages and verified addresses, or
      not-applicable reason: TBD
- [ ] CCIP directory entry, required lanes/tokens, and verified addresses, or
      not-applicable reason: TBD
- [ ] LayerZero EndpointV2/EID and Stargate asset/pathway evidence when
      applicable, or not-applicable reason: TBD

### Chain-specific EVM differences

_Gas token and decimals, wrapped-native availability, value-transfer rules, fee
floor, finality, simulation caveats. Write "none beyond standard EVM" when that
is verified._

### Validation

- [ ] `forge fmt --check`
- [ ] `forge build`
- [ ] `forge test --no-match-test "invariant_.*" --no-match-path "test/fork/**"`
- [ ] `pnpm format`
- [ ] Deployed bytecode/constructor inputs and owner checked on-chain.

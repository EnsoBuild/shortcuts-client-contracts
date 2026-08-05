## Add {{CHAIN_NAME}} (`{{CHAIN_ID}}`) contract support

Issue: `{{TICKET}}`

### Agent-preparable work

- [ ] Add `{{CHAIN_ID}}` to the canonical chain ID library.
- [ ] Inventory owner-dependent configuration; leave it blocked until the
      approved address is supplied.
- [ ] Configure explorer verification behavior.
- [ ] Research flashloan, CCIP, and LayerZero candidates from official
      documentation and verified explorer pages.
- [ ] Prepare only the deployers approved for launch scope.
- [ ] Add focused tests and prepare deployment/verification commands.

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
- [ ] Deployment transactions: TBD
- [ ] Verified contract pages: TBD
- [ ] Flashloan provider deployment pages and verified addresses, or
      not-applicable reason: TBD
- [ ] CCIP directory entry, required lanes/tokens, and verified addresses, or
      not-applicable reason: TBD
- [ ] LayerZero EndpointV2/EID and Stargate asset/pathway evidence when
      applicable, or not-applicable reason: TBD

### Validation

- [ ] `forge fmt --check`
- [ ] `forge test`
- [ ] `pnpm format`
- [ ] Deployed bytecode/constructor inputs and owner checked on-chain.

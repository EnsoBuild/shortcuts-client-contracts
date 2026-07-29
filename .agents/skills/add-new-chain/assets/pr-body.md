## Add {{CHAIN_NAME}} (`{{CHAIN_ID}}`) contract support

Issue: `{{TICKET}}`

### Scope

- [ ] Add `{{CHAIN_ID}}` to the canonical chain ID library.
- [ ] Configure the intended owner; do not leave an accidental placeholder owner.
- [ ] Configure explorer verification behavior.
- [ ] Configure only launch-scope deployers (core, flashloan, CCIP, LayerZero).
- [ ] Add flashloan lenders only for verified protocol deployments.
- [ ] Run actual deployments and commit truthful broadcast artifacts.
- [ ] Verify deployed contracts on the explorer.
- [ ] Confirm the configured owner and deployed contract state on-chain.

### Public evidence

- [ ] Chain documentation: TBD
- [ ] Deployment transactions: TBD
- [ ] Verified contract pages: TBD
- [ ] Optional integration provider documentation, or not-applicable reason: TBD

### Validation

- [ ] `forge fmt --check`
- [ ] `forge test`
- [ ] `pnpm format`
- [ ] Deployed bytecode/constructor inputs and owner checked on-chain.

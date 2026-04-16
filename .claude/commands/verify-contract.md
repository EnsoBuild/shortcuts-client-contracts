Manually verify a deployed contract when automatic verification during
deployment failed.

Arguments: $ARGUMENTS Format: `<DeployerScript.s.sol> <network>` Example:
`/verify-contract EnsoCCIPReceiverDeployer.s.sol tempo`

Follow these steps in order:

## 1. Parse arguments

Extract `<script>` and `<network>` from the arguments. If either is missing, ask
the user.

## 2. Validate RPC

The RPC env var follows the pattern `<NETWORK_UPPERCASE>_RPC_URL` (e.g.
`TEMPO_RPC_URL`).

- Source `.env` and check the variable is set:
  `source .env && echo ${<NETWORK_UPPERCASE>_RPC_URL}`
- If empty, tell the user to set it in `.env` and stop.

## 3. Resolve chain ID

Look up the chain ID for the network in `src/libraries/DataTypes.sol` (the
`ChainId` library). If the network is not found there, ask the user for the
chain ID.

## 4. Read the broadcast

Read `broadcast/<script>/<chainId>/run-latest.json` to extract:

- `contractAddress` from `transactions[*]`
- `contractName` from `transactions[*]`
- `arguments` (constructor args) from `transactions[*]`

If the broadcast directory or file does not exist, tell the user and stop. If
there are multiple transactions, list them and ask the user which contract to
verify.

## 5. Build constructor args encoding

From the broadcast `arguments` array and the contract source, determine the
constructor parameter types. Read the contract source file to find the
constructor signature (e.g. `constructor(address, address, address)`). Build the
encoding command: `cast abi-encode "constructor(<types>)" <arg1> <arg2> ...`

## 6. Determine verifier config

Use this mapping based on the network name (case-insensitive). This mirrors
`.bash/deploy.sh`:

**Tempo:**

- `--verifier-url "https://contracts.tempo.xyz/"`
- No extra flags needed (Foundry auto-detects Sourcify)

**Routescan networks (Berachain, Monad, Plasma):**

- `--verifier custom`
- `--verifier-url "https://api.routescan.io/v2/network/mainnet/evm/<chainId>/etherscan"`
- `--etherscan-api-key "verifyContract"`

**Blockscout networks with custom URLs:**

- Ink:
  `--verifier blockscout --verifier-url "https://explorer.inkonchain.com/api"`
- Plume: `--verifier blockscout --verifier-url "https://explorer.plume.org/api"`
- Katana:
  `--verifier blockscout --verifier-url "https://explorer.katanarpc.com/api"`
- MegaETH:
  `--verifier blockscout --verifier-url "https://megaeth.blockscout.com/api"`

**Blockscout networks (default pattern):**

- Gnosis and any not listed above that use blockscout:
  `--verifier blockscout --verifier-url "https://<network>.blockscout.com/api"`

**Etherscan networks (everything else):**

- `--verifier etherscan`
- `--etherscan-api-key` from `ETHEREUM_BLOCKSCAN_KEY` env var

If you are not sure which verifier to use for a network, check `.bash/deploy.sh`
first. If the network is not in deploy.sh either, search for verification docs
for that network (e.g. check their official docs site) and ask the user to
confirm before proceeding.

## 7. Present and run the command

Show the full `forge verify-contract` command to the user with all flags, then
run it:

```
forge verify-contract \
  --rpc-url "$<NETWORK_UPPERCASE>_RPC_URL" \
  <verifier flags from step 6> \
  --constructor-args $(cast abi-encode "constructor(<types>)" <args...>) \
  <contractAddress> \
  <sourcePath>:<contractName>
```

## 8. Handle failures

If verification fails:

- **"chain not supported"**: The verifier doesn't support this chain. Search for
  the network's official block explorer docs and try a different verifier.
- **"error decoding response body"**: The verifier URL format is wrong. Try
  adding or removing a trailing `/`, or try `/api` suffix.
- **"host only" URL error**: Add a trailing `/` or `/api` to the verifier URL.
- **Other errors**: Show the error to the user and suggest alternatives (e.g.
  try `--show-standard-json-input` and curl directly to the verifier API).

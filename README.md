# Enso Shortcuts Client Contracts

Client contracts for running Enso Shortcuts.

## Install

Requires [Foundry](https://getfoundry.sh/).

```bash
$ forge install
$ forge build
```

## Tests

```bash
$ forge test
```

## Deployment

Copy `.env.example` to `.env`, fill out required values.

```bash
$ forge script Deployer --broadcast --fork-url <network>
```

## Verification

Example of how manually verifying a contract with constructor args after deployment:

```sh
forge verify-contract \
--watch \
--chain polygon \
0xDb5b96dC4CE3E0E44d30279583F926363eFaE29f \
src/helpers/FeeSplitter.sol:FeeSplitter \
--verifier etherscan \
--etherscan-api-key <string:etherscan-api-ke> \
--constructor-args $(cast abi-encode "constructor(address,address[],uint16[])" "0x6AA68C46eD86161eB318b1396F7b79E386e88676" "[0xBfC330020E3267Cea008718f1712f1dA7F0d32A9,0x6AA68C46eD86161eB318b1396F7b79E386e88676]" "[1,1]")
```

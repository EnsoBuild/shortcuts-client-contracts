# Enso Shortcuts Client Contracts

Client contracts for running Enso Shortcuts.

## Install

Requires [Foundry](https://getfoundry.sh/).

```bash
$ forge install
$ pnpm install
$ pnpm foundry:update
$ forge build
```

---

## Tests

```bash
$ forge test
```

### Write BTTs with Bulloak

Requires [Bulloak](https://github.com/alexfertel/bulloak)

#### Writing Trees and Generating Solidity Scaffolds

1. **Create or Open a Tree File**

   Create a `<ContractName>.tree` file if it doesn’t exist, or open an existing
   one.  
   It’s recommended to write your test tree in ASCII format for clarity. For
   example:

   ```
   ERC4337CloneFactory_DelegateDeploy
   # when EnsoReceiver does not exist
   ## it should emit CloneDeployed event
   ## it should deploy clone
   ## it should initialize clone
   # when EnsoReceiver already exists
   ## it should revert
   ```

2. **Convert to Tree Structure**

   Convert your ASCII outline to a tree diagram using either:
   - [VSCode Ascii Tree Generator extension](https://marketplace.visualstudio.com/items?itemName=aprilandjan.ascii-tree-generator).
   - Any LLM (Large Language Model) or online tool.

   To avoid clutter, you can group multiple method trees in a single `.tree`
   file.  
   **Note:** Only one tree can be scaffolded at a time—comment out others before
   running `bulloak scaffold`.

   Example:

   ```tree
   // NOTE: this tree is commented out to exclude it from bulloak scaffold command
   // ERC4337CloneFactory_Deploy
   // ├── when EnsoReceiver does not exist
   // │   ├── it should emit CloneDeployed event
   // │   ├── it should deploy clone
   // │   └── it should initialize clone
   // └── when EnsoReceiver already exists
   //     └── it should revert

   ERC4337CloneFactory_DelegateDeploy
   ├── when EnsoReceiver does not exist
   │   ├── it should emit CloneDeployed event
   │   ├── it should deploy clone
   │   └── it should initialize clone
   └── when EnsoReceiver already exists
       └── it should revert
   ```

3. **Generate the Solidity Scaffold**

   Run the following command to generate the Solidity test scaffold:

   ```sh
   bulloak scaffold test/unit/concrete/factory/erc4337CloneFactory/ERC4337CloneFactory.tree
   ```

   This will generate a contract similar to:

   ```solidity
   // SPDX-License-Identifier: UNLICENSED
   pragma solidity 0.8.0;

   contract ERC4337CloneFactory_DelegateDeploy {
       function test_WhenEnsoReceiverDoesNotExist() external {
           // it should emit CloneDeployed event
           // it should deploy clone
           // it should initialize clone
       }

       function test_RevertWhen_EnsoReceiverAlreadyExists() external {
           // it should revert
       }
   }
   ```

4. **Finalize the Generated Contract**

   After generation, review and update the contract as needed:
   - Set the correct license identifier.
   - Adjust the pragma version if necessary.
   - Add any required imports.
   - Update the contract name and inheritance as appropriate.
     - Suggested naming pattern:
       `<ContractName>_<Method>[_When<Condition>][_As<Role>][_Unit|Int|Fork][_Concrete|Fuzz]_Test`.

---

## Deployment

Copy `.env.example` to `.env`, fill out required values.

```bash
$ forge script Deployer --broadcast --fork-url <network>
```

---

## Verification

Example of how manually verifying a contract with constructor args after
deployment:

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

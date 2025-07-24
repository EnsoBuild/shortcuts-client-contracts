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

### Unit & Integration Testing - Write BTTs with Bulloak

_Bulloak_ is a Solidity test generator based on the **Branching Tree Technique
(BTT)**.  
See the [Bulloak repo](https://github.com/alexfertel/bulloak) for full
documentation, examples, and advanced usage.

#### **Requirements**

- [Bulloak](https://github.com/alexfertel/bulloak) (install with
  `cargo install bulloak`)
- (Optional)
  [VSCode Ascii Tree Generator extension](https://marketplace.visualstudio.com/items?itemName=aprilandjan.ascii-tree-generator)
  for easier tree editing

#### **How to Write and Scaffold BTT Trees**

1. **Create a Tree File**

   Create a `<ContractName>.tree` file (e.g., `ERC4337CloneFactory.tree`).  
   Each tree describes the branching logic of a function or contract using ASCII
   art.

   **Example:**

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

   Use ASCII tree tools or an LLM to convert your outline to a tree with `├`,
   `└`, and `│` characters.  
   You can group multiple trees in a single file, but only one can be scaffolded
   at a time (comment out others).

   **Example:**

   ```tree
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

3. **Scaffold the Solidity Test**

   Run:

   ```sh
   bulloak scaffold path/to/YourContract.tree
   ```

   This generates a `.t.sol` test file with the contract and test stubs.

4. **Review and Finalize**
   - Set the correct SPDX license and pragma.
   - Add necessary imports.
   - Update the contract name and inheritance as needed.
   - **Naming pattern suggestion:**  
     `<ContractName>_<Method>[_When<Condition>][_As<Role>][_Unit|Int|Fork][_Concrete|Fuzz]_Test`

### Mutation Testing

Mutation testing helps you measure the effectiveness of your test suite by
introducing small changes ("mutants") to your code and checking if your tests
catch them.

#### **Requirements**

- [Certora Gambit](https://github.com/Certora/gambit) (for mutation generation)
- Node.js (for running the mutation test script)
- A working `gambit.config.json` (see below)

#### **Setup**

1. **Create or update your Gambit config**

   Make sure you have a `gambit.config.json` in your project root.  
   See [Certora Gambit docs](https://github.com/Certora/gambit) for config
   options.

2. **Generate Mutations**

   ```sh
   gambit mutate --json gambit.config.json
   ```

   This will create mutated versions of your contracts in `gambit_out/mutants/`.

3. **Run Mutation Tests**

   You can run mutation tests using the provided script:

   ```sh
   node ./mutationTest.mjs --matchContract 'EnsoReceiver_.*_Unit_Concrete_Test'
   ```

   - Use the `--matchContract` flag with a regex to select which test contracts
     to run against each mutant.
   - You can also use `--matchMutant` to filter which mutants to test (by
     contract name or pattern).

   **Example:**

   ```sh
   node ./mutationTest.mjs --matchContract 'EnsoReceiver_.*_Unit_Concrete_Test' --matchMutant EnsoReceiver
   ```

   This will run all test contracts matching the pattern against all mutants of
   `EnsoReceiver`.

   > **Tip:** You can use more complex regexes to match multiple contracts,
   > e.g.  
   > `--matchContract 'EnsoReceiver_.*_(Unit|Fork)_Concrete_Test'`

4. **(Optional) Automate with a Script**

   For more complex or repeated runs, you can create a JS script in `scripts/`,
   e.g.  
   [`scripts/runEnsoCheckoutMutationTests.mjs`](./scripts/runEnsoCheckoutMutationTests.mjs).

#### **Script Options and Advanced Usage**

The `mutationTest.mjs` script is based on
[ibourn/gambit-mutation-testing](https://github.com/ibourn/gambit-mutation-testing?tab=readme-ov-file#script-options-to-refine-test-execution).  
**For
a full list of available options and advanced usage, see the
[original script documentation](https://github.com/ibourn/gambit-mutation-testing?tab=readme-ov-file#script-options-to-refine-test-execution).**

Some useful options include:

- `--matchContract "<pattern>"` – Only run tests for contracts matching the
  regex.
- `--noMatchContract "<pattern>"` – Exclude contracts matching the regex.
- `--matchTest "<pattern>"` – Only run test functions matching the regex.
- `--noMatchTest "<pattern>"` – Exclude test functions matching the regex.
- `--matchMutant "<pattern>"` – Only test mutants for source files matching the
  pattern.
- `--verbose true` – Show detailed output in the console.
- `--debug true` – Save detailed logs to the `testLogs` folder.

#### **How It Works**

- The script will:
  - Backup the original contract file (in `src/`)
  - Replace it with each mutant, one at a time
  - Run your Foundry tests with the specified contract filter
  - Restore the original file after each mutant
  - Log results and mutation score

#### **Best Practices & Troubleshooting**

- **Always use a regex for `--matchContract`** if you want to match multiple
  contracts.  
  Example: `--matchContract 'EnsoReceiver_.*_Unit_Concrete_Test'`
- **Do not stage or commit files in `gambit_out/` or `tempBackup/`**—these are
  generated and temporary.
- If you see errors about missing files (e.g.,
  `ENOENT: no such file or directory, lstat 'delegate/EnsoReceiver.sol'`), make
  sure your source files are in `src/` and the script is up to date (see
  [#Path Issues](#path-issues) below).
- **Check your test coverage**: Surviving mutants indicate untested or weakly
  tested code paths.

#### **Path Issues**

If you reorganize your contracts, ensure the mutation script is updated to look
for source files in the correct location (e.g.,
`src/delegate/EnsoReceiver.sol`).

#### **Example Command Table**

| What you want to do               | Command Example                                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Run all mutants against all tests | `node ./mutationTest.mjs`                                                                                 |
| Only test EnsoReceiver mutants    | `node ./mutationTest.mjs --matchMutant EnsoReceiver`                                                      |
| Only run specific test contracts  | `node ./mutationTest.mjs --matchContract 'EnsoReceiver_.*_Unit_Concrete_Test'`                            |
| Combine both filters              | `node ./mutationTest.mjs --matchContract 'EnsoReceiver_.*_Unit_Concrete_Test' --matchMutant EnsoReceiver` |

---

**For more details and advanced script options, see the
[gambit-mutation-testing script documentation](https://github.com/ibourn/gambit-mutation-testing?tab=readme-ov-file#script-options-to-refine-test-execution).**

---

Let me know if you want this inserted directly, or if you want a more
concise/advanced version!

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

# Audit README: Enso CCIP Receiver

**Project:** Enso Shortcuts Client Contracts  
**Component:** EnsoCCIPReceiver & Chainlink CCIP Integration  
**Version:** 1.0.0  
**Audit Date:** [TBD]  
**PR:** [#60](https://github.com/EnsoBuild/shortcuts-client-contracts/pull/60)  
**Commit:** [0526e61](https://github.com/EnsoBuild/shortcuts-client-contracts/commit/0526e61e6e1a5a09d2e1b18c34c135d04673b0dd)

---

## Project Overview

The Enso CCIP Receiver is a destination-side contract that integrates Enso
Shortcuts with Chainlink's Cross-Chain Interoperability Protocol (CCIP). It
serves as a bridge endpoint that receives cross-chain messages containing ERC-20
tokens and executes Enso Shortcuts operations on the destination chain.

### Purpose

Enso Shortcuts is a composable DeFi routing system that enables complex
multi-protocol operations in a single transaction. The CCIP Receiver allows
users to initiate Shortcuts operations cross-chain by:

1. Sending tokens via CCIP from a source chain
2. Receiving tokens and execution data on the destination chain
3. Automatically routing tokens through Enso Shortcuts to execute complex DeFi
   operations

### Key Features

- **Replay Protection**: Message ID-based idempotency to prevent duplicate
  executions
- **Defensive Error Handling**: Non-reverting error handling with
  refund/quarantine mechanisms
- **Message Validation**: Strict validation of token shape (exactly one ERC-20
  with non-zero amount)
- **Safe Payload Decoding**: Non-reverting ABI decoding with comprehensive
  validation
- **Graceful Degradation**: Funds are safely handled even when execution fails

---

## Audit Scope

### In-Scope Contracts

| File                                    | Lines | Description                                             |
| --------------------------------------- | ----- | ------------------------------------------------------- |
| `src/bridge/EnsoCCIPReceiver.sol`       | 230   | Main receiver contract implementing CCIP callback logic |
| `src/interfaces/IEnsoCCIPReceiver.sol`  | 125   | Interface definition with error codes and events        |
| `src/interfaces/ITypeAndVersion.sol`    | 10    | Versioning interface                                    |
| `src/libraries/CCIPMessageDecoder.sol`  | 82    | Safe ABI decoder for CCIP message payloads              |
| `script/EnsoCCIPReceiverDeployer.s.sol` | 97    | Deployment script with multi-chain configuration        |

**Total Lines of Code:** ~544 SLOC

### Out-of-Scope

- Enso Router implementation (`src/router/EnsoRouter.sol`)
- Enso Shortcuts core (`src/EnsoShortcuts.sol`)
- Chainlink CCIP Router contracts (external dependency)
- Deployment infrastructure beyond the deployer script
- Off-chain message construction and sending logic
- Upstream Enso Shortcuts functionality (assumed to work correctly)

### Dependencies

- **Chainlink CCIP**: `chainlink-ccip` package (v1.6.2) - CCIPReceiver base
  contract
- **OpenZeppelin Contracts**: Access control (Ownable2Step), Pausable, SafeERC20
- **Enso Router**: Interface only - execution engine for Shortcuts

---

## Architecture & Components

### High-Level Architecture

```
┌─────────────────┐
│  Source Chain   │
│                 │
│  CCIP Router    │──────CCIP Message──────┐
│  (Chainlink)    │                         │
└─────────────────┘                         │
                                            ▼
                                    ┌─────────────────┐
                                    │ Destination     │
                                    │ Chain           │
                                    │                 │
                                    │  CCIP Router    │
                                    │  (Chainlink)    │
                                    └────────┬────────┘
                                             │
                                             │ _ccipReceive()
                                             ▼
                                    ┌─────────────────┐
                                    │ EnsoCCIPReceiver│
                                    │                 │
                                    │  1. Validate    │
                                    │  2. Decode      │
                                    │  3. Execute     │
                                    └────────┬────────┘
                                             │
                                             │ routeSingle()
                                             ▼
                                    ┌─────────────────┐
                                    │  Enso Router    │
                                    │                 │
                                    │  Executes       │
                                    │  Shortcuts      │
                                    └─────────────────┘
```

### Component Breakdown

#### 1. EnsoCCIPReceiver (`EnsoCCIPReceiver.sol`)

The main contract that implements the CCIP receiver interface. It inherits from:

- **CCIPReceiver**: Provides router gating and base CCIP functionality
- **Ownable2Step**: Two-step ownership transfer for security
- **Pausable**: Emergency pause mechanism
- **ITypeAndVersion**: Contract versioning

**Key State Variables:**

- `i_ensoRouter` (immutable): Enso Router address for executing Shortcuts
- `s_executedMessage` (mapping): Replay protection tracking

**Core Functions:**

- `_ccipReceive()`: Main entry point called by CCIP Router
- `execute()`: Self-callable function that routes tokens to Enso Router
- `pause()`/`unpause()`: Emergency controls
- `recoverTokens()`: Owner-only token recovery for quarantined funds

#### 2. CCIPMessageDecoder (`CCIPMessageDecoder.sol`)

Library that safely decodes CCIP message payloads without reverting. The payload
format is:

```
abi.encode(address receiver, bytes shortcutData)
```

**Key Properties:**

- Non-reverting: Returns `(success, receiver, shortcutData)` tuple
- Memory-safe assembly: Uses memory-safe assembly for efficient decoding
- Comprehensive validation: Checks alignment, bounds, and format

**Validation Checks:**

- Minimum length (96 bytes)
- Word alignment
- Offset bounds checking
- Length validation
- Overflow protection

#### 3. IEnsoCCIPReceiver (`IEnsoCCIPReceiver.sol`)

Interface defining the contract's external API and error classification system.

**Error Codes:**

- `NO_ERROR`: Message is valid and ready for execution
- `ALREADY_EXECUTED`: Message ID was previously processed (idempotent)
- `NO_TOKENS`: No tokens delivered
- `TOO_MANY_TOKENS`: More than one token delivered (not supported by Chainlink
  CCIP)
- `NO_TOKEN_AMOUNT`: Token amount is zero
- `MALFORMED_MESSAGE_DATA`: Payload cannot be decoded
- `ZERO_ADDRESS_RECEIVER`: Decoded receiver is zero address
- `PAUSED`: Contract is paused

**Refund Policies:**

- `NONE`: No action (for idempotent no-ops)
- `TO_RECEIVER`: Refund directly to decoded receiver
- `TO_ESCROW`: Quarantine funds in contract (for malformed messages)

---

## Trust Model & Assumptions

### Trusted Components

1. **Chainlink CCIP Router**:
   - Trusted to only call `_ccipReceive()` from authorized router address
   - Trusted to deliver tokens as specified in `destTokenAmounts`
   - Trusted message ID uniqueness and authenticity

2. **Enso Router**:
   - Trusted to execute Shortcuts correctly
   - Trusted to handle token approvals safely

### Trust Assumptions

1. **Message Format**: Sender constructs valid `abi.encode(address, bytes)`
   payload
2. **Token Standard**: Only ERC-20 tokens are delivered (no native ETH)
3. **Single Token**: CCIP currently delivers at most one token per message
4. **Router Immutability**: Enso Router address is immutable after deployment

### Untrusted Inputs

- **CCIP Message Payload** (`_message.data`): Must be validated and decoded
  safely
- **Token Addresses**: Delivered tokens could be malicious or non-standard
- **Message IDs**: Uniqueness assumed but replay protection enforced
- **Receiver Address**: Decoded from untrusted payload

---

## Roles & Permissions

### Owner

The contract owner has the following capabilities:

1. **Pause/Unpause** (`pause()`, `unpause()`):
   - Can pause contract to stop all new message processing
   - When paused, messages are refunded to receiver instead of executing
   - Two-step ownership transfer prevents accidental loss of control

2. **Token Recovery** (`recoverTokens()`):
   - Can recover any ERC-20 tokens held by the contract
   - Primary mechanism for recovering quarantined funds
   - Emits `TokensRecovered` event for transparency

3. **Ownership Transfer** (`transferOwnership()`, `acceptOwnership()`,
   `renounceOwnership()`):
   - Two-step process for security
   - Can renounce ownership (irreversible)

**Security Considerations:**

- Owner has significant power but cannot steal correctly routed funds
- Owner cannot modify router addresses (immutable)
- Two-step ownership prevents accidental transfers

### CCIP Router

- **Can Call**: `_ccipReceive()` (via CCIPReceiver base contract)
- **Access Control**: Enforced by CCIPReceiver's router check
- **Limitations**: Cannot call other functions directly

### Self (Contract)

- **Can Call**: `execute()` (self-call only)
- **Purpose**: Enables try/catch pattern for error handling (avoid reverting is
  recommended by Chainlink CCIP)
- **Access Control**: `msg.sender == address(this)` check

### Public

- **View Functions**: `getEnsoRouter()`, `wasMessageExecuted()`,
  `typeAndVersion()`
- **No State-Modifying Functions**: All state changes are permissioned

---

## Core Flows / State Machines

### Message Processing Flow

```
┌─────────────────────────────────────────────────────────┐
│              _ccipReceive() Entry Point                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────────┐
         │  _validateMessage()       │
         │                           │
         │  1. Replay Check          │
         │  2. Token Shape           │
         │  3. Payload Decode        │
         │  4. Receiver Check        │
         │  5. Pause Check           │
         └───────────┬───────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
   errorCode !=              errorCode ==
   NO_ERROR                  NO_ERROR
        │                         │
        │                         │
        ▼                         ▼
┌───────────────┐         ┌──────────────┐
│ Handle Error  │         │ Execute Path │
│               │         │              │
│ 1. Emit Event │         │ 1. Mark Done │
│ 2. Refund     │         │ 2. Try Exec  │
│    Policy     │         │ 3. Handle    │
└───────┬───────┘         │    Revert    │
        │                 └──────┬───────┘
        │                        │
        └────────────┬───────────┘
                     │
                     ▼
            ┌────────────────┐
            │   Complete     │
            └────────────────┘
```

### Error Handling State Machine

**Simplified Flow Diagram:**

```
                    Message Received
                          │
                          ▼
              ┌───────────────────────┐
              │  _validateMessage()  │
              │  (Sequential Checks) │
              └───────────┬───────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   ALREADY_EXECUTED   NO_ERROR       Error Codes
        │                 │         (See table)
        │                 │                 │
        ▼                 │                 │
    NONE (no-op)          │                 │
        │                 │                 │
        └─────────────────┴─────────────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │ Refund Policy │
                  │   Selection   │
                  └───────┬───────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
    NONE            TO_RECEIVER        TO_ESCROW
   (no-op)         (Refund)          (Quarantine)
        │                 │                 │
        │                 │                 │
        └─────────────────┴─────────────────┘
                          │
                          ▼
                    ┌──────────┐
                    │ Complete │
                    └──────────┘
```

**Complete Error Code → Refund Policy Mapping:**

| Error Code               | Validation Stage     | Refund Policy | Action             | Notes                                           |
| ------------------------ | -------------------- | ------------- | ------------------ | ----------------------------------------------- |
| `NO_ERROR`               | All checks pass      | NONE          | Execute Shortcut   | Proceeds to execution path                      |
| `ALREADY_EXECUTED`       | Replay check         | NONE          | Idempotent no-op   | Prevents duplicate processing, no state change  |
| `PAUSED`                 | Environment check    | TO_RECEIVER   | Refund to receiver | Receiver trusted (payload decoded successfully) |
| `NO_TOKENS`              | Token shape (step 1) | TO_ESCROW     | Quarantine         | No tokens delivered, cannot refund              |
| `TOO_MANY_TOKENS`        | Token shape (step 2) | TO_ESCROW     | Quarantine         | Not supported by CCIP protocol                  |
| `NO_TOKEN_AMOUNT`        | Token shape (step 3) | TO_ESCROW     | Quarantine         | Zero amount invalid                             |
| `MALFORMED_MESSAGE_DATA` | Payload decode       | TO_ESCROW     | Quarantine         | Cannot decode, receiver untrusted               |
| `ZERO_ADDRESS_RECEIVER`  | Receiver validation  | TO_ESCROW     | Quarantine         | Invalid receiver address                        |

**Validation Sequence (as executed in `_validateMessage()`):**

1. **Replay Protection** → Check `s_executedMessage[messageId]`
   - If true: Return `ALREADY_EXECUTED` (NONE refund)
2. **Token Shape Validation** → Check `destTokenAmounts`
   - If empty: Return `NO_TOKENS` (TO_ESCROW)
   - If length > 1: Return `TOO_MANY_TOKENS` (TO_ESCROW)
   - If amount == 0: Return `NO_TOKEN_AMOUNT` (TO_ESCROW)
3. **Payload Decoding** → Decode `(address, bytes)` from `data`
   - If decode fails: Return `MALFORMED_MESSAGE_DATA` (TO_ESCROW)
4. **Receiver Validation** → Check decoded receiver address
   - If zero address: Return `ZERO_ADDRESS_RECEIVER` (TO_ESCROW)
5. **Environment Check** → Check pause status
   - If paused: Return `PAUSED` (TO_RECEIVER)
6. **Success** → All checks pass
   - Return `NO_ERROR` → Proceed to execution

**Key Design Decisions:**

- **PAUSED → TO_RECEIVER**: Only error that refunds to receiver because payload
  is successfully decoded, so receiver address is trusted
- **All others → TO_ESCROW**: Either payload decoding failed (receiver
  untrusted) or message shape is invalid (no valid receiver)
- **ALREADY_EXECUTED → NONE**: Idempotent no-op; no refund needed as message was
  already handled

### Message Lifecycle States

1. **Unprocessed**: Message ID not in `s_executedMessage`
2. **Processing**: Inside `_ccipReceive()` execution
3. **Executed**: Marked in `s_executedMessage` mapping
   - **Sub-states**:
     - Successfully executed
     - Refunded to receiver
     - Quarantined in contract

**State Transitions:**

- Unprocessed → Processing: CCIP Router calls `_ccipReceive()`
- Processing → Executed (Success): Shortcut execution succeeds
- Processing → Executed (Refund): Error or revert triggers refund
- Processing → Executed (Quarantine): Malformed message quarantined
- Processing → Unprocessed: **Never** - replay protection prevents

### Replay Protection Mechanism

```
Message ID → s_executedMessage mapping
    │
    ├─ false: Process message
    └─ true:  Return immediately (idempotent no-op)
```

**Properties:**

- Once a message ID is marked as executed, it can never be processed again
- Prevents duplicate executions from CCIP retries or reorgs
- Applied before any state changes or token transfers

---

## Invariants & Safety Properties

### Critical Invariants

1. **Replay Protection Invariant**:

   ```
   For all messageId: if s_executedMessage[messageId] == true,
   then that messageId will never execute again
   ```

2. **No Token Loss Invariant**:

   ```
   For all messages: tokens are either:
   - Successfully routed to Enso Router
   - Refunded to receiver
   - Quarantined in contract (recoverable by owner)
   ```

3. **Immutable Router Invariant**:

   ```
   i_ensoRouter address cannot change after deployment
   ```

4. **Immutable CCIP Router Invariant**:

   ```
   CCIP Router address (passed to CCIPReceiver base) cannot change after deployment
   ```

   The CCIP Router address is set in the constructor via
   `CCIPReceiver(_ccipRouter)` and stored as immutable in the base contract.
   This ensures the receiver only accepts messages from the authorized Chainlink
   CCIP Router.

5. **Non-Reverting Invariant** (Critical CCIP Requirement):

   ```
   _ccipReceive() must NEVER revert; all errors must be handled gracefully
   ```

   This is a fundamental requirement for CCIP receivers. If `_ccipReceive()`
   reverts, it can cause critical issues with the CCIP protocol's message
   delivery system. All error paths must:
   - Use try/catch for external calls
   - Handle errors with refund/quarantine policies
   - Emit events instead of reverting
   - Never revert on validation failures

   This invariant is why the contract uses:
   - Non-reverting payload decoder
     (`CCIPMessageDecoder._tryDecodeMessageData()`)
   - Try/catch pattern for Shortcuts execution (`try this.execute(...)`)
   - Defensive error handling with refund/quarantine
   - No require/revert statements in `_ccipReceive()` error paths

6. **Idempotency Invariant**:

   ```
   Processing the same messageId multiple times has the same effect
   as processing it once (idempotent)
   ```

7. **Pause Invariant**:
   ```
   When paused, no new messages execute; all refunded to receiver
   ```

### Safety Properties

1. **Non-Reverting Error Handling** (Critical CCIP Requirement):
   - `_ccipReceive()` **must never revert** - this is a fundamental CCIP
     protocol requirement
   - Reverting from `_ccipReceive()` can cause protocol-level issues with
     message delivery
   - All errors are handled gracefully with appropriate refund/quarantine
     policies
   - This is why the contract uses non-reverting decoders, try/catch patterns,
     and defensive error handling
   - The entire error handling architecture (ErrorCode enum, RefundKind
     policies) exists to satisfy this invariant

2. **Safe Token Transfers**:
   - Uses `SafeERC20` for all token operations
   - Handles non-standard ERC-20 implementations

3. **Boundary Checks**:
   - Payload length validation prevents buffer overflows
   - Offset validation prevents out-of-bounds access
   - Amount validation prevents zero transfers

4. **Access Control**:
   - Router-only execution enforced by CCIPReceiver
   - Self-call only for `execute()` function
   - Owner-only for administrative functions

5. **Defensive Decoding**:
   - Non-reverting decoder prevents malicious payload crashes
   - Comprehensive validation of ABI structure
   - Safe assembly with overflow checks

### Failure Modes

1. **Enso Router Reverts**:
   - Caught by try/catch
   - Tokens refunded to receiver
   - Event emitted for monitoring

2. **Token Transfer Fails**:
   - SafeERC20 will revert (caught by try/catch)
   - Funds remain in contract (recoverable)

3. **Malformed Payload**:
   - Decoder returns failure
   - Funds quarantined in contract
   - Owner can recover via `recoverTokens()`

4. **Contract Paused**:
   - Validation returns `PAUSED` error
   - Funds refunded to receiver immediately
   - No execution attempted

---

## Upgradability & Admin Controls

### Upgradeability Model

The contract is NOT upgradeable.

### Admin Controls

1. **Pause Mechanism**:
   - **Function**: `pause()`, `unpause()`
   - **Access**: Owner only
   - **Effect**: Stops all new message processing
   - **Refund Policy**: Messages refunded to receiver when paused

2. **Token Recovery**:
   - **Function**: `recoverTokens(address, address, uint256)`
   - **Access**: Owner only
   - **Purpose**: Recover quarantined or accidentally sent tokens
   - **Event**: `TokensRecovered` for transparency

3. **Ownership Management**:
   - **Two-Step Transfer**: Prevents accidental loss
   - **Renounce**: Owner can renounce ownership (irreversible)
   - **Security**: Prevents accidental transfers to wrong address

### Admin Risk Assessment

**Low Risk:**

- Cannot modify execution logic
- Cannot change router address
- Cannot bypass validation

**Medium Risk:**

- Can pause contract (legitimate emergency action)
- Can recover tokens (requires off-chain coordination for quarantined funds)

**Mitigations:**

- Two-step ownership transfer
- Events for all admin actions
- Clear refund policies for paused state

---

## External Integrations & Dependencies

### Chainlink CCIP

**Dependency**: `chainlink-ccip/applications/CCIPReceiver.sol`  
**Version**: 1.6.2 **Source**: `dependencies/chainlink-ccip-1.6.2/`

All dependency versions and paths can be verified in `remappings.txt`.

**Integration Points:**

- Inherits from `CCIPReceiver` base contract
- Implements `_ccipReceive()` callback
- Uses `Client.Any2EVMMessage` data structure
- Router gating enforced by base contract

**Assumptions:**

- CCIP Router correctly calls authorized receiver
- Message IDs are unique across all chains
- Token delivery matches `destTokenAmounts` specification
- Router address remains constant (or changes require redeployment)

**Risk:**

- CCIP protocol bugs could affect receiver
- Router compromise could send malicious messages
- Network congestion could delay message delivery

### Enso Router

**Dependency**: `src/router/EnsoRouter.sol` (in-repo, not external)  
**Interface**: `src/interfaces/IEnsoRouter.sol`

The Enso Router is part of this repository (`shortcuts-client-contracts`), not
an external dependency. The receiver only uses the `IEnsoRouter` interface to
interact with it.

**Integration Points:**

- Calls `routeSingle(Token, bytes)` function
- Uses `forceApprove()` before routing
- Shortcuts execution could revert unexpectedly, but router is permissionless

**Note**: The Enso Router implementation itself is out of scope for this audit.
Only the interface usage and integration are relevant.

### OpenZeppelin Contracts

**Dependency**: `openzeppelin-contracts/`  
**Version**: 5.2.0 **Source**: `dependencies/@openzeppelin-contracts-5.2.0/`

**Contracts Used:**

- `Ownable2Step`: Two-step ownership transfer
- `Pausable`: Emergency pause functionality
- `SafeERC20`: Safe token transfer wrapper

**Risk**: Low - well-audited, battle-tested libraries

### Verifying Dependencies

All dependency versions, source locations, and remappings can be verified by
examining:

- `remappings.txt` - Contains all import remappings and dependency paths
- `foundry.toml` (dependencies section) - Contains git sources and versions
- `dependencies/` directory - Local copies of all dependencies

Key remappings for this audit:

- `chainlink-ccip=dependencies/chainlink-ccip-1.6.2/chains/evm/contracts/`
- `openzeppelin-contracts=dependencies/@openzeppelin-contracts-5.2.0/contracts/`

### Message Payload Format

**Expected Format**:

```solidity
abi.encode(
    address receiver,        // Destination for refunds
    bytes shortcutData      // Enso Shortcuts execution data
)
```

**Decoding**: Handled by `CCIPMessageDecoder._tryDecodeMessageData()`

**Validation**:

- Minimum 96 bytes (address + offset + length word)
- Word-aligned offsets
- Bounds checking
- Length validation

---

## Known Issues, Non-Goals, and Out-of-Scope

### Known Issues

1. **Single Token Limitation**:
   - Currently supports only one ERC-20 token per message
   - Multiple tokens cause quarantine (by design)
   - Future: Could be extended if CCIP adds multi-token support

2. **No Gas Validation**:
   - No gas estimation or validation is performed on-chain
   - Gas estimation and limits must be handled off-chain when constructing
     messages
   - Execution may fail if insufficient gas is provided by CCIP Router

3. **No Native ETH Support**:
   - Only ERC-20 tokens are supported
   - Native ETH deliveries would cause issues

4. **Quarantine Recovery**:
   - Quarantined funds require manual owner intervention
   - No automatic recovery mechanism
   - Owner must identify and recover funds off-chain

### Non-Goals

1. **Multi-Token Support**:
   - Not supported by CCIP protocol currently
   - Would require significant redesign

2. **Cross-Chain State Verification**:
   - No verification of source chain state
   - Relies entirely on CCIP message delivery

3. **Rate Limiting**:
   - No built-in rate limiting
   - Relies on CCIP Router and network congestion

4. **Gas Optimization**:
   - Not a primary concern for this receiver
   - Focus is on safety and correctness

### Out-of-Scope

1. **Enso Router Security**:
   - Assumed to be secure and correct
   - Not part of this audit scope

2. **Message Construction**:
   - Off-chain message building not audited
   - Sender responsibility to create valid payloads

3. **CCIP Protocol Itself**:
   - Chainlink's CCIP protocol not audited
   - Assumed to work correctly

4. **Frontend/UI**:
   - User-facing interfaces out of scope
   - Focus on smart contract security only

---

## Testing & Verification

### Test Coverage

**Location**: `test/unit/concrete/bridge/ensoCCIPReceiver/`

**Test Structure**: Branching Tree Technique (BTT) with Bulloak, and fuzz tests

### Running Tests

```bash
# Run all CCIP-related unit tests
pnpm test:enso_ccip:unit

# Run specific test file
forge test --match-path 'test/unit/concrete/bridge/ensoCCIPReceiver/*.t.sol'

# Run with verbose output
forge test -vvv
```

---

## Deployment & Network Info

### Deployment Script

**File**: `script/EnsoCCIPReceiverDeployer.s.sol`

**Parameters**:

- `owner`: Contract owner address
- `ccipRouter`: Chainlink CCIP Router address (chain-specific)
- `ensoRouter`: Enso Router address (chain-specific)

### Supported Chains

The deployer script supports the following chains (as of current commit):

| Chain     | Chain ID | CCIP Router                                  | Enso Router                                  |
| --------- | -------- | -------------------------------------------- | -------------------------------------------- |
| Ethereum  | `1`      | `0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Optimism  | `10`     | `0x3206695CaE29952f4b0c22a169725a865bc8Ce0f` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Binance   | `56`     | `0x34B03Cb9086d7D758AC55af71584F81A598759FE` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Gnosis    | `100`    | `0x4aAD6071085df840abD9Baf1697d5D5992bDadce` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Unichain  | `130`    | `0x68891f5F96695ECd7dEdBE2289D1b73426ae7864` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Polygon   | `137`    | `0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Sonic     | `146`    | `0xB4e1Ff7882474BB93042be9AD5E1fA387949B860` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| zkSync    | `324`    | `0x748Fd769d81F5D94752bf8B0875E9301d0ba71bB` | `0x1BD8CefD703CF6b8fF886AD2E32653C32bc62b5C` |
| World     | `480`    | `0x5fd9E4986187c56826A3064954Cfa2Cf250cfA0f` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Hyper     | `999`    | `0x13b3332b66389B1467CA6eBd6fa79775CCeF65ec` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Base      | `8453`   | `0x881e3A65B4d4a04dD529061dd0071cf975F58bCD` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Plasma    | `9745`   | `0xcDca5D374e46A6DDDab50bD2D9acB8c796eC35C3` | `0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7` |
| Arbitrum  | `42161`  | `0x141fa059441E0ca23ce184B6A78bafD2A517DdE8` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Avalanche | `43114`  | `0xF4c7E640EdA248ef95972845a62bdC74237805dB` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Ink       | `57073`  | `0xca7c90A52B44E301AC01Cb5EB99b2fD99339433A` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Linea     | `59144`  | `0x549FEB73F2348F6cD99b9fc8c69252034897f06C` | `0xA146d46823f3F594B785200102Be5385CAfCE9B5` |
| Berachain | `80094`  | `0x71a275704c283486fBa26dad3dd0DB78804426eF` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |
| Plume     | `98866`  | `0x5C4f4622AD0EC4a47e04840db7E9EcA8354109af` | `0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F` |
| Katana    | `747474` | `0x7c19b79D2a054114Ab36ad758A36e92376e267DA` | `0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf` |

**Note**: Most chains use the standard Enso Router address
`0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf`. The following chains use different
Enso Router addresses:

- **zkSync** (`324`): `0x1BD8CefD703CF6b8fF886AD2E32653C32bc62b5C`
- **Plasma** (`9745`): `0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7`
- **Linea** (`59144`): `0xA146d46823f3F594B785200102Be5385CAfCE9B5`
- **Plume** (`98866`): `0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F`

### Deployment Steps

1. **Set Environment Variables**:

   ```bash
   export PRIVATE_KEY=<deployer_private_key>
   ```

2. **Update Owner Address**:
   - Modify deployer script or pass as parameter
   - **TODO**: Currently hardcoded check fails - needs owner address set

3. **Deploy**:

   ```bash
   forge script EnsoCCIPReceiverDeployer --broadcast --fork-url <network_rpc>
   ```

4. **Verify Contract**:
   ```bash
   forge verify-contract \
     --chain <chain_name> \
     <contract_address> \
     src/bridge/EnsoCCIPReceiver.sol:EnsoCCIPReceiver \
     --constructor-args $(cast abi-encode "constructor(address,address,address)" <owner> <ccip_router> <enso_router>)
   ```

### Deployment Checklist

- [ ] Verify CCIP Router address for target chain
- [ ] Verify Enso Router address for target chain
- [ ] Set owner address (use multi-sig recommended)
- [ ] Deploy contract
- [ ] Verify contract on block explorer
- [ ] Test pause/unpause functionality
- [ ] Test with small test message
- [ ] Set up monitoring for events

### Post-Deployment

1. **Monitoring**:
   - Monitor `MessageValidationFailed` events
   - Monitor `MessageQuarantined` events
   - Monitor `ShortcutExecutionFailed` events
   - Track quarantined token balances

2. **Emergency Procedures**:
   - Pause contract if issues detected
   - Recover quarantined funds if needed
   - Coordinate with Chainlink if CCIP issues

---

## Additional Resources

### Documentation

- [Enso Shortcuts Documentation](https://docs.enso.finance/)
- [Chainlink CCIP Documentation](https://docs.chain.link/ccip)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

---

## Contact & Questions

For questions about this audit scope or the contracts, please contact the Enso
team or refer to the PR discussion:
[#60](https://github.com/EnsoBuild/shortcuts-client-contracts/pull/60)

---

**Document Version**: 1.0  
**Last Updated**: [TBD]  
**Next Review**: Post-audit

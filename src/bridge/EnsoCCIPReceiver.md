# EnsoCCIPReceiver

**Component:** EnsoCCIPReceiver & Chainlink CCIP Integration

---

## Overview

The EnsoCCIPReceiver is a destination-side contract that integrates Enso
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

## Architecture

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

### Contract Inheritance

The contract inherits from:

- **CCIPReceiver**: Provides router gating and base CCIP functionality
- **Ownable2Step**: Two-step ownership transfer for security
- **Pausable**: Emergency pause mechanism
- **ITypeAndVersion**: Contract versioning

### Key State Variables

- `i_ensoRouter` (immutable): Enso Router address for executing Shortcuts
- `s_executedMessage` (mapping): Replay protection tracking

### Core Functions

- `_ccipReceive()`: Main entry point called by CCIP Router
- `execute()`: Self-callable function that routes tokens to Enso Router
- `pause()`/`unpause()`: Emergency controls
- `recoverTokens()`: Owner-only token recovery for quarantined funds

---

## Message Payload Format

### Expected Format

```solidity
abi.encode(
    address receiver,        // Destination for refunds
    bytes shortcutData       // Enso Shortcuts execution data
)
```

### Decoding

Handled by `CCIPMessageDecoder._tryDecodeMessageData()`

### Validation Checks

- Minimum 96 bytes (address + offset + length word)
- Word-aligned offsets
- Bounds checking
- Length validation

---

## Error Codes & Refund Policies

### Error Codes

| Error Code               | Description                                      |
| ------------------------ | ------------------------------------------------ |
| `NO_ERROR`               | Message is valid and ready for execution         |
| `ALREADY_EXECUTED`       | Message ID was previously processed (idempotent) |
| `NO_TOKENS`              | No tokens delivered                              |
| `TOO_MANY_TOKENS`        | More than one token delivered                    |
| `NO_TOKEN_AMOUNT`        | Token amount is zero                             |
| `MALFORMED_MESSAGE_DATA` | Payload cannot be decoded                        |
| `ZERO_ADDRESS_RECEIVER`  | Decoded receiver is zero address                 |
| `PAUSED`                 | Contract is paused                               |

### Refund Policies

| Policy        | Description                                       |
| ------------- | ------------------------------------------------- |
| `NONE`        | No action (for idempotent no-ops)                 |
| `TO_RECEIVER` | Refund directly to decoded receiver               |
| `TO_ESCROW`   | Quarantine funds in contract (malformed messages) |

### Error Code → Refund Policy Mapping

| Error Code               | Refund Policy | Action             |
| ------------------------ | ------------- | ------------------ |
| `NO_ERROR`               | NONE          | Execute Shortcut   |
| `ALREADY_EXECUTED`       | NONE          | Idempotent no-op   |
| `PAUSED`                 | TO_RECEIVER   | Refund to receiver |
| `NO_TOKENS`              | TO_ESCROW     | Quarantine         |
| `TOO_MANY_TOKENS`        | TO_ESCROW     | Quarantine         |
| `NO_TOKEN_AMOUNT`        | TO_ESCROW     | Quarantine         |
| `MALFORMED_MESSAGE_DATA` | TO_ESCROW     | Quarantine         |
| `ZERO_ADDRESS_RECEIVER`  | TO_ESCROW     | Quarantine         |

---

## Message Processing Flow

```
┌─────────────────────────────────────────────────────┐
│              _ccipReceive() Entry Point              │
└────────────────────┬────────────────────────────────┘
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

### Validation Sequence

1. **Replay Protection** → Check `s_executedMessage[messageId]`
2. **Token Shape Validation** → Check `destTokenAmounts`
3. **Payload Decoding** → Decode `(address, bytes)` from `data`
4. **Receiver Validation** → Check decoded receiver address
5. **Environment Check** → Check pause status

---

## Roles & Permissions

### Owner

1. **Pause/Unpause** (`pause()`, `unpause()`):
   - Can pause contract to stop all new message processing
   - When paused, messages are refunded to receiver instead of executing
   - Two-step ownership transfer prevents accidental loss of control

2. **Token Recovery** (`recoverTokens()`):
   - Can recover any ERC-20 tokens held by the contract
   - Primary mechanism for recovering quarantined funds
   - Emits `TokensRecovered` event for transparency

3. **Ownership Transfer**:
   - Two-step process for security
   - Can renounce ownership (irreversible)

### CCIP Router

- Can call `_ccipReceive()` via CCIPReceiver base contract
- Access control enforced by CCIPReceiver's router check

### Self (Contract)

- Can call `execute()` (self-call only)
- Enables try/catch pattern for error handling

### Public

- View functions: `getEnsoRouter()`, `wasMessageExecuted()`, `typeAndVersion()`

---

## Invariants

1. **Replay Protection**: Once a message ID is marked as executed, it can never
   be processed again

2. **No Token Loss**: Tokens are either successfully routed, refunded to
   receiver, or quarantined (recoverable by owner)

3. **Immutable Router**: `i_ensoRouter` address cannot change after deployment

4. **Non-Reverting**: `_ccipReceive()` must never revert; all errors are handled
   gracefully

5. **Idempotency**: Processing the same messageId multiple times has the same
   effect as processing it once

---

## Dependencies

- **Chainlink CCIP**: `chainlink-ccip` package (v1.6.2) - CCIPReceiver base
  contract
- **OpenZeppelin Contracts**: Access control (Ownable2Step), Pausable, SafeERC20
- **Enso Router**: Interface only - execution engine for Shortcuts

---

## Testing

### Test Location

`test/unit/concrete/bridge/ensoCCIPReceiver/`

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

## Known Limitations

1. **Single Token**: Only one ERC-20 token per message is supported
2. **No Native ETH**: Only ERC-20 tokens are supported
3. **Manual Recovery**: Quarantined funds require owner intervention
4. **Gas Limits**: Gas estimation must be handled off-chain when constructing
   messages

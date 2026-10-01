// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Token } from "./IEnsoRouter.sol";

/// Shared intent format: the EIP-712 message IntentRouter executes, and the blob inside the
/// ephemeral executor's address.
struct Intent {
    uint16 version;
    uint256 chainId; // execution chain
    uint256 nonce; // unordered; distinguishes otherwise-identical intents
    uint64 start;
    uint64 deadline;
    address owner; // signer / refund beneficiary; the only account funds move from
    address recipient; // where tokensOut minimums are measured
    address keeper; // the only account that may execute; address(0) = any caller
    KeeperFee keeperFee;
    Token[] tokensIn; // pulled from the owner (router) or required delivered (ephemeral); ERC721 word 2 = tokenId
    Token[] tokensOut; // minimums measured at the recipient; ERC721 second word is a count
    bytes route; // committed shortcut data; empty = the keeper supplies the route and tokensOut is the constraint
}

struct KeeperFee {
    address token; // address(0) for native token
    uint256 intentFee;
    uint256 refundFee;
}

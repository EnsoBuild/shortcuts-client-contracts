// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { Token } from "./IEnsoRouter.sol";

/// Shared intent format. IntentRouter signs and executes it directly; the ephemeral executor's
/// v2 blob is the same struct (triggers → tokensIn, Constrained flattened, mode derived from route).
struct Intent {
    uint16 version;
    uint256 chainId; // execution chain
    uint256 nonce; // unordered; distinguishes otherwise-identical intents
    uint64 start;
    uint64 deadline;
    address owner; // signer; the only account funds move from
    address recipient; // where tokensOut minimums are measured
    Token[] tokensIn; // pulled from the owner; ERC721 second word is a tokenId
    Token[] tokensOut; // minimums measured at the recipient; ERC721 second word is a count
    KeeperFee keeperFee;
    bytes route; // committed shortcut data; empty = the keeper supplies the route and tokensOut is the constraint
}

struct KeeperFee {
    address token; // address(0) for native token
    uint256 intentFee;
    uint256 refundFee;
}

interface IIntentRouter {
    function execute(
        Intent calldata intent,
        bytes calldata signature,
        bytes calldata route
    )
        external
        returns (bytes memory response);

    function cancel(uint256 nonce) external;

    function hash(Intent calldata intent) external view returns (bytes32);
}

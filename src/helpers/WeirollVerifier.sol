// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SignatureVerifier } from "../libraries/SignatureVerifier.sol";

// @audit no replay protection (aka. nonce), is it ok?
contract WeirollVerifier {
    using SignatureVerifier for bytes32;

    function verify(
        address signer,
        bytes32[] calldata commands,
        bytes[] calldata state,
        bytes calldata signature
    )
        public
        pure
        returns (bool)
    {
        bytes32 messageHash = getMessageHash(commands, state);
        bytes32 ethSignedMessageHash = messageHash.getEthSignedMessageHash();

        return ethSignedMessageHash.recoverSigner(signature) == signer;
    }

    function getMessageHash(bytes32[] calldata commands, bytes[] calldata state) public pure returns (bytes32) {
        return keccak256(abi.encode(commands, state));
    }
}

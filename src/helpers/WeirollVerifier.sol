// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ECDSA } from "solady/utils/ECDSA.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

contract WeirollVerifier {

    function verify(
        address signer,
        bytes32[] calldata commands,
        bytes[] calldata state,
        bytes calldata signature
    )
        public
        view
        returns (bool)
    {
        bytes32 messageHash = getMessageHash(commands, state);
        bytes32 ethSignedMessageHash = SignatureCheckerLib.toEthSignedMessageHash(messageHash);

        return ECDSA.recoverCalldata(ethSignedMessageHash, signature) == signer;
    }

    function getMessageHash(bytes32[] calldata commands, bytes[] calldata state) public pure returns (bytes32) {
        return keccak256(abi.encode(commands, state));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC1271Wallet {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

error ERC1271Revert(bytes error);
error InvalidSignatureLength(uint256 length);
error InvalidSignatureV();

library SignatureVerifier {
    bytes4 private constant ERC1271_SUCCESS = 0x1626ba7e;

    function isValidSig(address _signer, bytes32 _hash, bytes calldata _signature) internal view returns (bool) {
        // Try ERC-1271 verification
        if (_signer.code.length > 0) {
            try IERC1271Wallet(_signer).isValidSignature(_hash, _signature) returns (bytes4 magicValue) {
                bool isValid = magicValue == ERC1271_SUCCESS;
                return isValid;
            } catch (bytes memory err) {
                revert ERC1271Revert(err); // TODO: revert or return false?
            }
        }

        // ecrecover verification
        if (_signature.length != 65) revert InvalidSignatureLength(_signature.length); // TODO: revert or return false?
        bytes32 r = bytes32(_signature[0:32]);
        bytes32 s = bytes32(_signature[32:64]);
        uint8 v = uint8(_signature[64]);
        if (v != 27 && v != 28) revert InvalidSignatureV(); // TODO: revert or return false?
        return ecrecover(_hash, v, r, s) == _signer;
    }
}

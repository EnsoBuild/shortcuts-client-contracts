// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract HyperCoreHelpers {
    uint256 public constant VERSION = 1;
    bytes1 private constant ENCODING_VERSION = 0x01;
    bytes3 private constant ACTION_6 = 0x000006;

    function encodeAction6(
        address _receiver,
        uint256 _tokenIndex,
        uint256 _amountInCoreWei
    )
        external
        pure
        returns (bytes memory payload)
    {
        /// forge-lint: disable-next-item(unsafe-typecast)
        payload = abi.encodePacked(
            ENCODING_VERSION, ACTION_6, abi.encode(_receiver, uint64(_tokenIndex), uint64(_amountInCoreWei))
        );
    }
}

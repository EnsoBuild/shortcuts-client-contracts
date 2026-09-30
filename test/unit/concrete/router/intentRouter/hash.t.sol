// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { Token, TokenType } from "../../../../../src/interfaces/IEnsoRouter.sol";
import { Intent, KeeperFee } from "../../../../../src/interfaces/IIntentRouter.sol";
import { IntentRouter } from "../../../../../src/router/IntentRouter.sol";
import { Test } from "forge-std/Test.sol";
import { MessageHashUtils } from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

/// Golden vector produced by ethers v6 `TypedDataEncoder` for the intent below, with the
/// domain { name: "IntentRouter", version: "1", chainId: 31337, verifyingContract: ROUTER }.
/// It pins the type string, the nested Token[]/KeeperFee hashing and the domain, so an SDK
/// signing with the same `types` produces signatures this contract accepts.
contract IntentRouter_Hash_Unit_Concrete_Test is Test {
    address internal constant ROUTER = 0x7777777777777777777777777777777777777777;
    bytes32 internal constant STRUCT_HASH = 0xd6e3ddb7f4561e0dc62af4290fa579262eb3fd0921a1165112bbeef1fb09c933;
    bytes32 internal constant DIGEST = 0xd20e25270bad84f0abcf5199e64067bba51f395e20363fcc93505f68a4644a5d;
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function test_WhenHashedAgainstTheReferenceEncoder() external {
        vm.chainId(31_337);
        deployCodeTo("IntentRouter.sol:IntentRouter", abi.encode(address(0xBEEF)), ROUTER);
        IntentRouter router = IntentRouter(ROUTER);

        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token({
            tokenType: TokenType.ERC20, data: abi.encode(0x3333333333333333333333333333333333333333, uint256(100 ether))
        });
        tokensIn[1] = Token({
            tokenType: TokenType.ERC721, data: abi.encode(0x4444444444444444444444444444444444444444, uint256(42))
        });
        Token[] memory tokensOut = new Token[](2);
        tokensOut[0] = Token({ tokenType: TokenType.Native, data: abi.encode(uint256(1 ether)) });
        tokensOut[1] = Token({
            tokenType: TokenType.ERC1155,
            data: abi.encode(0x5555555555555555555555555555555555555555, uint256(9), uint256(3))
        });
        Intent memory intent = Intent({
            version: 1,
            chainId: 31_337,
            nonce: 7,
            start: 1_700_000_000,
            deadline: 1_700_003_600,
            owner: 0x1111111111111111111111111111111111111111,
            recipient: 0x2222222222222222222222222222222222222222,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            keeperFee: KeeperFee({
                token: 0x6666666666666666666666666666666666666666, intentFee: 5 ether, refundFee: 1 ether
            }),
            route: hex"deadbeef"
        });

        // it should match the ethers TypedDataEncoder digest
        assertEq(router.hash(intent), DIGEST);

        // it should compose the domain from the exposed EIP-712 fields
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            router.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract)
        );
        assertEq(MessageHashUtils.toTypedDataHash(domainSeparator, STRUCT_HASH), DIGEST);
    }
}

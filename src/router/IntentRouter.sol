// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { EnsoShortcuts } from "../EnsoShortcuts.sol";
import { Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { Intent, KeeperFee } from "../interfaces/IIntent.sol";
import { IIntentRouter } from "../interfaces/IIntentRouter.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuardTransient } from "openzeppelin-contracts/utils/ReentrancyGuardTransient.sol";
import { ECDSA } from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

/// @title IntentRouter
/// @notice Executes EIP-712 signed intents through a dedicated EnsoShortcuts. Users approve this
///         contract; the intent's keeper submits it with a route; tokens only ever move from the
///         intent's owner, and only the amounts the owner signed.
contract IntentRouter is IIntentRouter, EIP712, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    bytes32 private constant TOKEN_TYPEHASH = keccak256("Token(uint8 tokenType,bytes data)");
    bytes32 private constant KEEPER_FEE_TYPEHASH =
        keccak256("KeeperFee(address token,uint256 intentFee,uint256 refundFee)");
    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(uint16 version,uint256 chainId,uint256 nonce,uint64 start,uint64 deadline,address owner,address recipient,address keeper,KeeperFee keeperFee,Token[] tokensIn,Token[] tokensOut,bytes route)KeeperFee(address token,uint256 intentFee,uint256 refundFee)Token(uint8 tokenType,bytes data)"
    );

    address public immutable shortcuts;

    /// @notice Unordered nonces: bit `nonce % 256` of word `nonce / 256`, per owner.
    mapping(address owner => mapping(uint256 word => uint256 bits)) public nonceBitmap;

    event IntentExecuted(address indexed owner, uint256 nonce);
    event IntentCancelled(address indexed owner, uint256 nonce);

    error NotKeeper();
    error WrongChain();
    error TooEarly();
    error Expired();
    error InvalidSignature();
    error NonceUsed();
    error Unconstrained();
    error AmountTooLow(Token token, uint256 amount, uint256 minAmount);
    error UnsupportedTokenType(TokenType tokenType);

    constructor() EIP712("IntentRouter", "1") {
        shortcuts = address(new EnsoShortcuts(address(this)));
    }

    /// @notice Execute a signed intent. The intent's keeper only, or anyone when it is zero.
    /// @param intent The signed intent
    /// @param signature The owner's EIP-712 signature over hash(intent); ECDSA or ERC-1271
    /// @param route Shortcut data forwarded to EnsoShortcuts when the intent commits none
    function executeIntent(
        Intent calldata intent,
        bytes calldata signature,
        bytes calldata route
    )
        external
        nonReentrant
        returns (bytes memory response)
    {
        if (intent.keeper != address(0) && msg.sender != intent.keeper) {
            revert NotKeeper();
        }
        if (intent.chainId != block.chainid) {
            revert WrongChain();
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (block.timestamp < intent.start) {
            revert TooEarly();
        }
        // forge-lint: disable-next-item(block-timestamp)
        if (block.timestamp > intent.deadline) {
            revert Expired();
        }
        if (!_isValidSignature(intent.owner, hash(intent), signature)) {
            revert InvalidSignature();
        }
        _useNonce(intent.owner, intent.nonce);

        // A committed route is its own constraint; a keeper route needs an outcome floor.
        bool committed = intent.route.length > 0;
        if (!committed && intent.tokensOut.length == 0) {
            revert Unconstrained();
        }

        // Fee off the top, before the route, so it never depends on what the route leaves behind.
        _payFee(intent.keeperFee, intent.owner);
        // forge-lint: disable-next-line(uninitialized-local)
        for (uint256 i; i < intent.tokensIn.length; ++i) {
            _transfer(intent.tokensIn[i], intent.owner);
        }

        // Validation is by measured outcome, never by inspecting the route: snapshot at the
        // recipient after the pulls, route, assert every delta clears its committed minimum.
        uint256[] memory minimums = new uint256[](intent.tokensOut.length);
        uint256[] memory before = new uint256[](intent.tokensOut.length);
        // forge-lint: disable-next-line(uninitialized-local)
        for (uint256 i; i < intent.tokensOut.length; ++i) {
            minimums[i] = _minOut(intent.tokensOut[i]);
            // forge-lint: disable-next-item(require-revert-in-loop)
            if (minimums[i] == 0) {
                revert Unconstrained();
            }
            before[i] = _balance(intent.tokensOut[i], intent.recipient);
        }

        response = _execute(committed ? intent.route : route);

        // forge-lint: disable-next-line(uninitialized-local)
        for (uint256 i; i < intent.tokensOut.length; ++i) {
            uint256 after_ = _balance(intent.tokensOut[i], intent.recipient);
            // Explicit ordering: a recipient balance decrease is zero delivered, not a Panic.
            uint256 amountOut = after_ > before[i] ? after_ - before[i] : 0;
            // forge-lint: disable-next-item(require-revert-in-loop)
            if (amountOut < minimums[i]) {
                revert AmountTooLow(intent.tokensOut[i], amountOut, minimums[i]);
            }
        }

        // forge-lint: disable-next-line(reentrancy-events)
        emit IntentExecuted(intent.owner, intent.nonce);
    }

    /// @notice Retire one of the caller's nonces so no intent carrying it can execute.
    function cancel(uint256 nonce) external {
        _useNonce(msg.sender, nonce);
        emit IntentCancelled(msg.sender, nonce);
    }

    /// @notice The EIP-712 digest the owner signs.
    function hash(Intent calldata intent) public view returns (bytes32) {
        KeeperFee calldata fee = intent.keeperFee;
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    INTENT_TYPEHASH,
                    intent.version,
                    intent.chainId,
                    intent.nonce,
                    intent.start,
                    intent.deadline,
                    intent.owner,
                    intent.recipient,
                    intent.keeper,
                    keccak256(abi.encode(KEEPER_FEE_TYPEHASH, fee.token, fee.intentFee, fee.refundFee)),
                    _hashTokens(intent.tokensIn),
                    _hashTokens(intent.tokensOut),
                    keccak256(intent.route)
                )
            )
        );
    }

    /// ECDSA first so EOAs and EIP-7702 accounts verify without a call, then ERC-1271 for contract wallets.
    function _isValidSignature(address signer, bytes32 digest, bytes calldata signature) private view returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return true;
        }
        return SignatureChecker.isValidERC1271SignatureNow(signer, digest, signature);
    }

    function _useNonce(address owner, uint256 nonce) private {
        uint256 word = nonce >> 8;
        uint256 bit = 1 << (nonce & 0xff);
        uint256 bits = nonceBitmap[owner][word];
        if (bits & bit != 0) {
            revert NonceUsed();
        }
        nonceBitmap[owner][word] = bits | bit;
    }

    /// Paid to the executing caller. No refund branch exists here — funds never leave the owner
    /// before execution — so only intentFee applies; refundFee is carried for the shared format.
    function _payFee(KeeperFee calldata fee, address from) private {
        if (fee.intentFee == 0) {
            return;
        }
        if (fee.token == address(0)) {
            revert UnsupportedTokenType(TokenType.Native);
        }
        // `from` is the verified signer, not the caller.
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        IERC20(fee.token).safeTransferFrom(from, msg.sender, fee.intentFee);
    }

    function _execute(bytes calldata data) private returns (bytes memory response) {
        bool success;
        (success, response) = shortcuts.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(response, 32), mload(response))
            }
        }
    }

    /// Pull one committed token from the owner into shortcuts. Native cannot be pulled from a wallet.
    /// `from` is the verified signer, not the caller.
    function _transfer(Token calldata token, address from) private {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.ERC20) {
            (IERC20 erc20, uint256 amount) = abi.decode(token.data, (IERC20, uint256));
            // forge-lint: disable-next-line(calls-loop, arbitrary-send-erc20)
            erc20.safeTransferFrom(from, shortcuts, amount);
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            // forge-lint: disable-next-line(calls-loop)
            erc721.safeTransferFrom(from, shortcuts, tokenId);
        } else if (tokenType == TokenType.ERC1155) {
            (IERC1155 erc1155, uint256 tokenId, uint256 amount) = abi.decode(token.data, (IERC1155, uint256, uint256));
            // forge-lint: disable-next-line(calls-loop)
            erc1155.safeTransferFrom(from, shortcuts, tokenId, amount, "");
        } else {
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert UnsupportedTokenType(tokenType);
        }
    }

    /// Out-side read, exactly as EnsoRouter's safeRoute: ERC721 is a collection count.
    function _balance(Token calldata token, address account) private view returns (uint256) {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            // forge-lint: disable-next-line(calls-loop)
            return erc20.balanceOf(account);
        } else if (tokenType == TokenType.Native) {
            return account.balance;
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721,) = abi.decode(token.data, (IERC721, uint256));
            // forge-lint: disable-next-line(calls-loop)
            return erc721.balanceOf(account);
        } else {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            // forge-lint: disable-next-line(calls-loop)
            return erc1155.balanceOf(account, tokenId);
        }
    }

    /// The committed outcome minimum: the last data word for every type.
    function _minOut(Token calldata token) private pure returns (uint256) {
        TokenType tokenType = token.tokenType;

        if (tokenType == TokenType.Native) {
            return abi.decode(token.data, (uint256));
        } else if (tokenType == TokenType.ERC1155) {
            (,, uint256 amount) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return amount;
        } else {
            (, uint256 amount) = abi.decode(token.data, (address, uint256));
            return amount;
        }
    }

    function _hashTokens(Token[] calldata tokens) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](tokens.length);
        // forge-lint: disable-next-line(uninitialized-local)
        for (uint256 i; i < tokens.length; ++i) {
            hashes[i] = keccak256(abi.encode(TOKEN_TYPEHASH, uint8(tokens[i].tokenType), keccak256(tokens[i].data)));
        }
        return keccak256(abi.encodePacked(hashes));
    }
}

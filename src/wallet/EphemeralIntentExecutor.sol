// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Token, TokenLib, TokenType } from "../libraries/TokenLib.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

enum Mode {
    ROUTE,
    CONSTRAINED
}

struct Intent {
    uint16 version;
    uint256 chainId; // mismatch = refund-only branch
    uint256 nonce; // distinguishes otherwise-identical intents (usefull if self-destruct is ever removed)
    uint64 start;
    uint64 deadline;
    address refundRecipient;
    Token[] triggers; // every entry must pass; amounts are the delivery minimums
    Token keeperFee; // flat, committed; paid to the executing caller
    Mode mode;
    bytes payload; // ROUTE: shortcut data for the router; CONSTRAINED: abi.encode(Constrained)
}

struct Constrained {
    address recipient;
    Token[] tokensOut; // minimums measured at the recipient; v2 may replace with a dutch-auction decay
    address exclusiveKeeper;
    uint64 exclusiveUntil;
}

interface IEphemeralFactory {
    function context() external view returns (bytes memory route, Token[] memory sweep, address keeper, address router);
}

// EnsoRouter's entry point, typed over the canonical Token (ABI-identical to the
// declaration in IEnsoRouter.sol; unified when the router migrates to TokenLib).
interface IEnsoRouter {
    function routeSingle(Token calldata tokenIn, bytes calldata data) external payable returns (bytes memory);

    function routeMulti(Token[] calldata tokensIn, bytes calldata data) external payable returns (bytes memory);
}

contract EphemeralIntentExecutor {
    error TooEarly();
    error Underfunded();
    error Exclusive();
    error Insufficient();
    error SendFailed();

    /// The entire lifecycle runs in the constructor: the contract never deposits runtime
    /// code, and a selfdestruct in the creating transaction deletes the account (EIP-6780),
    /// so the address stays reusable and the code-deposit cost is never paid.
    constructor(Intent memory intent) {
        // Read once, before any external interaction — a nested executeIntent() in the
        // same transaction overwrites the factory's transient context.
        (bytes memory route, Token[] memory sweep, address keeper, address router) =
            IEphemeralFactory(msg.sender).context();

        // A zero refund recipient would burn native at the selfdestruct and silently
        // strand every swept ERC20. Substitute the keeper (the factory's caller — never
        // zero) rather than validate: a revert here, before branch selection, would be
        // a permanent brick on every branch, including a perfectly executable one.
        address beneficiary = intent.refundRecipient == address(0) ? keeper : intent.refundRecipient;

        if (block.chainid != intent.chainId) {
            // Wrong-chain recovery: execution is unreachable here by construction, so
            // sweep immediately — no deadline to wait out, nothing to race.
            _refund(intent, sweep, keeper, beneficiary);
        } else if (block.timestamp > intent.deadline) {
            _refund(intent, sweep, keeper, beneficiary);
        } else {
            if (block.timestamp < intent.start) {
                revert TooEarly();
            }
            _requireTriggers(intent.triggers);
            // Fee off the top, before the route: approvals and call value hand the
            // remaining balances to the router, so a fee paid afterwards would depend
            // on the route deliberately leaving it behind.
            _payFee(intent.keeperFee, keeper, true);
            _run(intent, route, keeper, router);
        }

        // Remaining native balance rides the account deletion.
        selfdestruct(payable(beneficiary));
    }

    function _run(Intent memory intent, bytes memory route, address keeper, address router) private {
        if (intent.mode == Mode.ROUTE) {
            // The committed payload is the shortcut data; the route argument is ignored.
            _route(router, intent.payload, intent.triggers);
        } else {
            _constrained(intent, route, keeper, router);
        }
    }

    function _constrained(Intent memory intent, bytes memory route, address keeper, address router) private {
        Constrained memory c = abi.decode(intent.payload, (Constrained));

        if (block.timestamp <= c.exclusiveUntil && keeper != c.exclusiveKeeper) {
            revert Exclusive();
        }
        // No outcome floor means the route is an unconstrained full-balance grant:
        // reject empty constraint lists and zero minimums. Execute branch — a revert
        // here is liveness-only, bounded by the deadline.
        if (c.tokensOut.length == 0) {
            revert Insufficient();
        }

        // Validation is by measured outcome, never by inspecting the route: snapshot at
        // the recipient, route, assert every delta clears its committed minimum.
        uint256[] memory before = new uint256[](c.tokensOut.length);
        for (uint256 i; i < c.tokensOut.length; ++i) {
            if (_amount(c.tokensOut[i]) == 0) {
                revert Insufficient();
            }
            before[i] = TokenLib.balance(c.tokensOut[i], c.recipient);
        }

        _route(router, route, intent.triggers);

        for (uint256 i; i < c.tokensOut.length; ++i) {
            uint256 after_ = TokenLib.balance(c.tokensOut[i], c.recipient);
            // Explicit ordering: checked subtraction would Panic on a recipient balance
            // decrease instead of reverting Insufficient.
            if (after_ < before[i] || after_ - before[i] < _amount(c.tokensOut[i])) {
                revert Insufficient();
            }
        }
    }

    /// The executor's single protocol-facing call: the router's route entry with the
    /// trigger tokens re-amounted to their live balances, so shortcuts execute against
    /// what was actually delivered — amounts are never hardcoded at commit time. The
    /// data is the inner shortcut payload; committed and keeper bytes alike choose
    /// neither a target nor a router function. Approvals go to the router, exact
    /// balances, revoked after the call: approvals survive selfdestruct into the next
    /// incarnation, so none may outlive it.
    function _route(address router, bytes memory data, Token[] memory triggers) private {
        _approveTriggers(triggers, router, true);
        uint256 value = TokenLib.value(triggers);
        if (triggers.length == 1) {
            IEnsoRouter(router).routeSingle{ value: value }(_liveToken(triggers[0]), data);
        } else {
            Token[] memory tokensIn = new Token[](triggers.length);
            for (uint256 i; i < triggers.length; ++i) {
                tokensIn[i] = _liveToken(triggers[i]);
            }
            IEnsoRouter(router).routeMulti{ value: value }(tokensIn, data);
        }
        _approveTriggers(triggers, router, false);
    }

    /// A trigger entry with its amount replaced by the current balance. ERC721 carries
    /// a tokenId and passes through unchanged. Native is re-amounted in the data as
    /// well as msg.value: current routers take the amount from msg.value, but some
    /// older versions read it from the encoding.
    function _liveToken(Token memory token) private view returns (Token memory) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return Token({ tokenType: tokenType, data: abi.encode(address(this).balance) });
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            return Token({ tokenType: tokenType, data: abi.encode(erc20, erc20.balanceOf(address(this))) });
        } else if (tokenType == TokenType.ERC1155) {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return Token({
                tokenType: tokenType, data: abi.encode(erc1155, tokenId, erc1155.balanceOf(address(this), tokenId))
            });
        }
        return token;
    }

    function _requireTriggers(Token[] memory triggers) private view {
        for (uint256 i; i < triggers.length; ++i) {
            if (TokenLib.balance(triggers[i], address(this)) < _amount(triggers[i])) {
                revert Underfunded();
            }
        }
    }

    function _refund(Intent memory intent, Token[] memory sweep, address keeper, address to) private {
        // Fee first, best-effort, so permissionless refunds are self-incentivizing; then
        // committed and keeper-listed tokens to the beneficiary. Native rides the
        // selfdestruct.
        _payFee(intent.keeperFee, keeper, false);
        for (uint256 i; i < intent.triggers.length; ++i) {
            _sweep(intent.triggers[i], to);
        }
        for (uint256 i; i < sweep.length; ++i) {
            _sweep(sweep[i], to);
        }
    }

    function _approveTriggers(Token[] memory triggers, address spender, bool grant) private {
        for (uint256 i; i < triggers.length; ++i) {
            TokenLib.approve(triggers[i], spender, grant);
        }
    }

    function _payFee(Token memory fee, address to, bool strict) private {
        // Strict (execute branch): typed reads, fail loudly on a bad committed fee.
        // Best-effort (refund branches): fully tolerant — a malformed or codeless fee
        // token must never block the exit, so zero means "skip the fee".
        uint256 amount = strict ? _amount(fee) : _tryAmount(fee);
        if (amount == 0 || to == address(0)) {
            return;
        }
        bool success;
        uint256 held = strict ? TokenLib.balance(fee, address(this)) : _tryBalance(fee);
        if (held >= amount) {
            success = _tryTransfer(fee, to, amount);
        }
        if (strict && !success) {
            revert SendFailed();
        }
    }

    /// The committed amount: a trigger minimum, fee amount, or constraint minimum.
    function _amount(Token memory token) private pure returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return abi.decode(token.data, (uint256));
        } else if (tokenType == TokenType.ERC20) {
            (, uint256 amount_) = abi.decode(token.data, (IERC20, uint256));
            return amount_;
        } else if (tokenType == TokenType.ERC721) {
            (, uint256 amount_) = abi.decode(token.data, (IERC721, uint256));
            return amount_;
        } else {
            (,, uint256 amount_) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return amount_;
        }
    }

    /// Tolerant amount read: zero for undecodable committed data instead of a revert.
    function _tryAmount(Token memory token) private pure returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return token.data.length < 32 ? 0 : _word(token.data, 0);
        } else if (tokenType == TokenType.ERC1155) {
            return token.data.length < 96 ? 0 : _word(token.data, 2);
        } else {
            return token.data.length < 64 ? 0 : _word(token.data, 1);
        }
    }

    /// Tolerant balance probe: zero for malformed data, codeless assets, or reverting
    /// reads. ERC721 shares ERC20's balanceOf selector, so one probe covers both.
    function _tryBalance(Token memory token) private view returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return address(this).balance;
        }
        if (token.data.length < (tokenType == TokenType.ERC1155 ? 96 : 64)) {
            return 0;
        }
        address asset = address(uint160(_word(token.data, 0)));
        bytes memory probe = tokenType == TokenType.ERC1155
            ? abi.encodeCall(IERC1155.balanceOf, (address(this), _word(token.data, 1)))
            : abi.encodeCall(IERC20.balanceOf, (address(this)));
        (bool success, bytes memory ret) = asset.staticcall(probe);
        if (!success || ret.length < 32) {
            return 0;
        }
        return abi.decode(ret, (uint256));
    }

    /// Best-effort send; false on failure or malformed data, never reverts. Reads the
    /// encoding by raw words rather than abi.decode, so dirty committed bytes cannot
    /// revert a refund.
    function _tryTransfer(Token memory token, address to, uint256 amount_) private returns (bool success) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            (success,) = to.call{ value: amount_ }("");
            return success;
        }
        if (token.data.length < (tokenType == TokenType.ERC1155 ? 96 : 64)) {
            return false;
        }
        address asset = address(uint160(_word(token.data, 0)));
        if (tokenType == TokenType.ERC20) {
            success = _tryTransfer(asset, to, amount_);
        } else if (tokenType == TokenType.ERC721) {
            (success,) = asset.call(abi.encodeCall(IERC721.transferFrom, (address(this), to, _word(token.data, 1))));
        } else {
            (success,) = asset.call(
                abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, _word(token.data, 1), amount_, ""))
            );
        }
    }

    /// transfer() tolerant of missing return data; false for false-returning tokens
    /// and for any non-canonical return shape — the bool decoder's validity check
    /// would revert on a dirty word, and this helper sits on the refund path.
    /// `== 1`, not `!= 0`: this also serves the strict fee path, and `!= 0` would
    /// widen "fee paid" to any non-zero word. The length check must stay inside the
    /// boolean expression — _word is an unguarded mload relying on && short-circuit.
    function _tryTransfer(address token, address to, uint256 amount_) private returns (bool success) {
        bytes memory ret;
        (success, ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount_)));
        success = success && (ret.length == 0 || (ret.length >= 32 && _word(ret, 0) == 1));
    }

    /// Best-effort full-balance sweep with a tolerant probe: garbage or malformed
    /// committed assets — including addresses that are codeless on the wrong chain —
    /// must never block an exit. Raw words, never abi.decode: the address- and
    /// contract-typed decoders carry validators that revert on short data or dirty
    /// address words, and a revert here is a permanent brick. Native is skipped; it
    /// rides the selfdestruct.
    function _sweep(Token memory token, address to) private {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return;
        }
        if (token.data.length < (tokenType == TokenType.ERC1155 ? 96 : 64)) {
            return; // tolerant skip — a require here would re-create the brick
        }
        address asset = address(uint160(_word(token.data, 0)));
        if (tokenType == TokenType.ERC20) {
            _sweep(asset, to);
        } else if (tokenType == TokenType.ERC721) {
            (bool success,) =
                asset.call(abi.encodeCall(IERC721.transferFrom, (address(this), to, _word(token.data, 1))));
            (success); // best-effort
        } else {
            uint256 tokenId = _word(token.data, 1);
            (bool success, bytes memory ret) =
                asset.staticcall(abi.encodeCall(IERC1155.balanceOf, (address(this), tokenId)));
            if (!success || ret.length < 32) {
                return;
            }
            uint256 held = abi.decode(ret, (uint256));
            if (held == 0) {
                return;
            }
            (success,) = asset.call(abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, tokenId, held, "")));
        }
    }

    /// ERC20-only sweep for keeper-listed addresses.
    function _sweep(address token, address to) private {
        if (token == address(0)) {
            return;
        }
        (bool success, bytes memory ret) = token.staticcall(abi.encodeCall(IERC20.balanceOf, (address(this))));
        if (!success || ret.length < 32) {
            return;
        }
        uint256 held = abi.decode(ret, (uint256));
        if (held == 0) {
            return;
        }
        _tryTransfer(token, to, held);
    }

    function _word(bytes memory data, uint256 index) private pure returns (uint256 word) {
        assembly ("memory-safe") {
            word := mload(add(add(data, 0x20), shl(5, index)))
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IEnsoRouter, Token, TokenType } from "../interfaces/IEnsoRouter.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    KeeperFee keeperFee; // flat, committed; paid to the executing caller
    Mode mode;
    bytes payload; // ROUTE: shortcut data for the router; CONSTRAINED: abi.encode(Constrained)
}

struct Constrained {
    address recipient;
    Token[] tokensOut; // minimums measured at the recipient; v2 may replace with a dutch-auction decay
    address exclusiveKeeper;
    uint64 exclusiveUntil;
}

struct KeeperFee {
    address token; // address(0) for native token
    uint256 intentFee;
    uint256 refundFee;
}

interface IEphemeralFactory {
    function context() external view returns (bytes memory route, Token[] memory sweep, address keeper, address router);
}

contract EphemeralIntentExecutor {
    using SafeERC20 for IERC20;

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
            if (_minOut(c.tokensOut[i]) == 0) {
                revert Insufficient();
            }
            before[i] = _balance(c.tokensOut[i], c.recipient);
        }

        _route(router, route, intent.triggers);

        for (uint256 i; i < c.tokensOut.length; ++i) {
            uint256 after_ = _balance(c.tokensOut[i], c.recipient);
            // Explicit ordering: checked subtraction would Panic on a recipient balance
            // decrease instead of reverting Insufficient.
            if (after_ < before[i] || after_ - before[i] < _minOut(c.tokensOut[i])) {
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
        uint256 value = _value(triggers);
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

    function _refund(Intent memory intent, Token[] memory sweep, address keeper, address to) private {
        // Fee first, best-effort, so permissionless refunds are self-incentivizing; then
        // committed and keeper-listed tokens to the beneficiary. Native rides the
        // selfdestruct.
        _payFee(intent.keeperFee, keeper, false);
        // The fee token itself, whether or not it is a trigger or keeper-listed: the
        // address is reusable, so a fee-token balance left behind would fund another
        // refund fee on the next execution, and any keeper could repeat that until the
        // balance fell below one fee. Emptying it here caps every exit at one fee.
        _sweep(intent.keeperFee.token, to);
        for (uint256 i; i < intent.triggers.length; ++i) {
            _sweep(intent.triggers[i], to);
        }
        for (uint256 i; i < sweep.length; ++i) {
            _sweep(sweep[i], to);
        }
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
            // Balance side via the tolerant probe: for ERC721 it checks presence of the
            // committed tokenId (in-side semantics — the router pulls, and the sweep
            // returns, that exact token), and tolerance is safe here because the amount
            // side stays strict, so a malformed trigger still reverts on this branch.
            if (_tryBalance(triggers[i]) < _amount(triggers[i])) {
                revert Underfunded();
            }
        }
    }

    function _approveTriggers(Token[] memory triggers, address spender, bool grant) private {
        for (uint256 i; i < triggers.length; ++i) {
            _approve(triggers[i], spender, grant);
        }
    }

    function _payFee(KeeperFee memory fee, address to, bool execute) private {
        // Strict (execute branch): typed reads, fail loudly on a bad committed fee.
        // Best-effort (refund branches): fully tolerant — a malformed or codeless fee
        // token must never block the exit, so zero means "skip the fee".
        uint256 amount = execute ? fee.intentFee : fee.refundFee;
        if (amount == 0 || to == address(0)) {
            return;
        }
        bool success;
        // Blocking read on the execute branch: a codeless or non-conforming fee token
        // reverts here, liveness-only, bounded by the deadline. Refund branches use the
        // tolerant probe. Native (address(0)) is a raw balance read and cannot fail.
        uint256 held =
            execute && fee.token != address(0) ? IERC20(fee.token).balanceOf(address(this)) : _tryBalance(fee.token);
        if (held >= amount) {
            if (fee.token == address(0)) {
                (success,) = to.call{ value: amount }("");
            } else {
                success = _tryTransfer(fee.token, to, amount);
            }
        }
        if (execute && !success) {
            revert SendFailed();
        }
    }

    /// Grant or revoke the router's pull rights over one delivered token. forceApprove:
    /// a reused address can hold a stale allowance from a previous incarnation, which
    /// breaks approve-from-nonzero tokens like USDT. Native is skipped; it travels as
    /// call value.
    function _approve(Token memory token, address spender, bool grant) private {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return;
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            erc20.forceApprove(spender, grant ? erc20.balanceOf(address(this)) : 0);
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            if (grant) {
                erc721.approve(spender, tokenId);
            } else {
                // Tolerance is scoped to the moved case only: EIP-721 rejects approve
                // from a non-owner, so a pulled token cannot be revoked and needs no
                // revoke. If the executor STILL owns it, stay strict — swallowing a
                // failed revoke here would let the approval outlive the account into
                // its next incarnation. Execute branch, so a revert is liveness-only.
                (bool ok, bytes memory o) = address(erc721).staticcall(abi.encodeCall(IERC721.ownerOf, (tokenId)));
                if (ok && o.length >= 32 && address(uint160(_word(o, 0))) == address(this)) {
                    erc721.approve(address(0), tokenId);
                }
            }
        } else {
            (IERC1155 erc1155,,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            erc1155.setApprovalForAll(spender, grant);
        }
    }

    /// Call value for the router: the full native balance when a native entry exists,
    /// zero otherwise — never chosen by the keeper.
    function _value(Token[] memory tokens) private view returns (uint256) {
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i].tokenType == TokenType.Native) {
                return address(this).balance;
            }
        }
        return 0;
    }

    /// The committed outcome minimum. Differs from _amount only for ERC721, where the
    /// out-side second word is a minimum COUNT — the id of a freshly minted position
    /// cannot be known at commit time — exactly as EnsoRouter's safeRoute reads it.
    function _minOut(Token memory token) private pure returns (uint256) {
        if (token.tokenType == TokenType.ERC721) {
            (, uint256 count) = abi.decode(token.data, (IERC721, uint256));
            return count;
        }
        return _amount(token);
    }

    /// The committed amount: a trigger minimum or constraint minimum.
    function _amount(Token memory token) private pure returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return abi.decode(token.data, (uint256));
        } else if (tokenType == TokenType.ERC20) {
            (, uint256 amount_) = abi.decode(token.data, (IERC20, uint256));
            return amount_;
        } else if (tokenType == TokenType.ERC721) {
            // The second word is a tokenId, not a quantity — reading it as an amount
            // makes any tokenId >= 2 fail the trigger check. Owning an NFT means one.
            return 1;
        } else {
            (,, uint256 amount_) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return amount_;
        }
    }

    /// Strict, typed balance read — reverts on a non-conforming asset. For committed
    /// tokens on the execute path, where garbage should fail loudly.
    function _balance(Token memory token, address account) private view returns (uint256) {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return account.balance;
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            return erc20.balanceOf(account);
        } else if (tokenType == TokenType.ERC721) {
            // Collection-count read, exactly as EnsoRouter's out-side check: the ERC721
            // second word is direction-dependent — a tokenId when pulling a known token
            // in, a minimum COUNT for outcomes whose id cannot be known at commit time
            // (a freshly minted LP position). Specific-tokenId presence for triggers
            // and fees is the in-side concern, handled by _tryBalance's ownerOf probe.
            (IERC721 erc721,) = abi.decode(token.data, (IERC721, uint256));
            return erc721.balanceOf(account);
        } else {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            return erc1155.balanceOf(account, tokenId);
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
        if (tokenType == TokenType.ERC721) {
            // Presence of the committed tokenId: 1 if this contract owns it, else 0.
            (bool ok, bytes memory owner) = asset.staticcall(abi.encodeCall(IERC721.ownerOf, (_word(token.data, 1))));
            if (!ok || owner.length < 32) {
                return 0;
            }
            return address(uint160(_word(owner, 0))) == address(this) ? 1 : 0;
        }
        bytes memory probe = tokenType == TokenType.ERC1155
            ? abi.encodeCall(IERC1155.balanceOf, (address(this), _word(token.data, 1)))
            : abi.encodeCall(IERC20.balanceOf, (address(this)));
        return _tryRead(asset, probe);
    }

    /// Tolerant balance probe by address, native/ERC20 only: the raw native balance for
    /// address(0), zero for codeless assets or reverting reads. Serves the refund-side
    /// fee payment and the keeper-listed sweep, where a bad address must never revert.
    function _tryBalance(address token) private view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return _tryRead(token, abi.encodeCall(IERC20.balanceOf, (address(this))));
    }

    /// Tolerant uint read: staticcall the probe, zero on failure or a short return.
    function _tryRead(address target, bytes memory probe) private view returns (uint256) {
        (bool success, bytes memory ret) = target.staticcall(probe);
        if (!success || ret.length < 32) {
            return 0;
        }
        return abi.decode(ret, (uint256));
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
            uint256 held = _tryRead(asset, abi.encodeCall(IERC1155.balanceOf, (address(this), tokenId)));
            if (held == 0) {
                return;
            }
            (bool success,) =
                asset.call(abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, tokenId, held, "")));
            (success); // best-effort
        }
    }

    /// ERC20-only sweep for keeper-listed addresses.
    function _sweep(address token, address to) private {
        if (token == address(0)) {
            return;
        }
        uint256 held = _tryBalance(token);
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

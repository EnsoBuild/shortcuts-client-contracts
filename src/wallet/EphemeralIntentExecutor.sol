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
    bytes payload; // ROUTE: router calldata; CONSTRAINED: abi.encode(Constrained)
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

        if (block.chainid != intent.chainId) {
            // Wrong-chain recovery: execution is unreachable here by construction, so
            // sweep immediately — no deadline to wait out, nothing to race.
            _refund(intent, sweep, keeper);
        } else if (block.timestamp > intent.deadline) {
            _refund(intent, sweep, keeper);
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
        selfdestruct(payable(intent.refundRecipient));
    }

    function _run(Intent memory intent, bytes memory route, address keeper, address router) private {
        if (intent.mode == Mode.ROUTE) {
            // The committed payload is router calldata; the route argument is ignored.
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

        // Validation is by measured outcome, never by inspecting the route: snapshot at
        // the recipient, route, assert every delta clears its committed minimum.
        uint256[] memory before = new uint256[](c.tokensOut.length);
        for (uint256 i; i < c.tokensOut.length; ++i) {
            before[i] = TokenLib.balance(c.tokensOut[i], c.recipient);
        }

        _route(router, route, intent.triggers);

        for (uint256 i; i < c.tokensOut.length; ++i) {
            if (TokenLib.balance(c.tokensOut[i], c.recipient) - before[i] < _amount(c.tokensOut[i])) {
                revert Insufficient();
            }
        }
    }

    /// The executor's single protocol-facing call. The target is the router the factory
    /// fixed at deployment and the value defers to the native trigger, so a keeper (or a
    /// committed program) chooses calldata only — the executor can never be made to
    /// approve or call anything else. Its own approvals go to the router, exact amounts,
    /// revoked after the call: approvals survive selfdestruct into the next incarnation,
    /// so none may outlive it.
    function _route(address router, bytes memory data, Token[] memory triggers) private {
        _approveTriggers(triggers, router, true);
        (bool success, bytes memory ret) = router.call{ value: TokenLib.value(triggers) }(data);
        if (!success) {
            // Bubble the inner revert reason.
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        _approveTriggers(triggers, router, false);
    }

    function _requireTriggers(Token[] memory triggers) private view {
        for (uint256 i; i < triggers.length; ++i) {
            if (TokenLib.balance(triggers[i], address(this)) < _amount(triggers[i])) {
                revert Underfunded();
            }
        }
    }

    function _refund(Intent memory intent, Token[] memory sweep, address keeper) private {
        // Fee first, best-effort, so permissionless refunds are self-incentivizing; then
        // committed and keeper-listed tokens to the committed recipient. Native rides the
        // selfdestruct.
        _payFee(intent.keeperFee, keeper, false);
        for (uint256 i; i < intent.triggers.length; ++i) {
            _sweep(intent.triggers[i], intent.refundRecipient);
        }
        for (uint256 i; i < sweep.length; ++i) {
            _sweep(sweep[i], intent.refundRecipient);
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

    /// transfer() tolerant of missing return data; false for false-returning tokens.
    function _tryTransfer(address token, address to, uint256 amount_) private returns (bool success) {
        bytes memory ret;
        (success, ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount_)));
        success = success && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    /// Best-effort full-balance sweep with a tolerant probe: garbage assets — including
    /// committed addresses that are codeless on the wrong chain — must never block an
    /// exit. Native is skipped; it rides the selfdestruct.
    function _sweep(Token memory token, address to) private {
        TokenType tokenType = token.tokenType;
        if (tokenType == TokenType.Native) {
            return;
        } else if (tokenType == TokenType.ERC20) {
            (IERC20 erc20,) = abi.decode(token.data, (IERC20, uint256));
            _sweep(address(erc20), to);
        } else if (tokenType == TokenType.ERC721) {
            (IERC721 erc721, uint256 tokenId) = abi.decode(token.data, (IERC721, uint256));
            (bool success,) = address(erc721).call(abi.encodeCall(IERC721.transferFrom, (address(this), to, tokenId)));
            (success); // best-effort
        } else {
            (IERC1155 erc1155, uint256 tokenId,) = abi.decode(token.data, (IERC1155, uint256, uint256));
            (bool success, bytes memory ret) =
                address(erc1155).staticcall(abi.encodeCall(IERC1155.balanceOf, (address(this), tokenId)));
            if (!success || ret.length < 32) {
                return;
            }
            uint256 held = abi.decode(ret, (uint256));
            if (held == 0) {
                return;
            }
            (success,) = address(erc1155)
                .call(abi.encodeCall(IERC1155.safeTransferFrom, (address(this), to, tokenId, held, "")));
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

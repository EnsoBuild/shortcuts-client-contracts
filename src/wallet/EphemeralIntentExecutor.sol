// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum Mode {
    ROUTE,
    CONSTRAINED
}

struct Trigger {
    address token; // address(0) = native
    uint256 minAmount; // executor balance required before execution may run
}

struct Fee {
    address token; // a triggered token, or address(0) for native
    uint256 amount; // flat, committed; paid to the executing caller
}

struct Intent {
    uint16 version;
    uint256 chainId; // mismatch = refund-only branch
    uint256 nonce; // distinguishes otherwise-identical intents (usefull if self-destruct is ever removed)
    uint64 starttime;
    uint64 deadline;
    address refundRecipient;
    Trigger[] triggers; // every entry must pass
    Fee keeperFee;
    Mode mode;
    bytes payload; // ROUTE: router calldata; CONSTRAINED: abi.encode(Constrained)
}

struct Constrained {
    address recipient;
    address tokenOut; // address(0) = native
    uint256 minAmountOut; // committed pre-bridge; v2 may replace with a dutch-auction decay
    address exclusiveKeeper;
    uint64 exclusiveUntil;
}

interface IEphemeralFactory {
    function context()
        external
        view
        returns (bytes memory route, address[] memory sweep, address keeper, address router);
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
        (bytes memory route, address[] memory sweep, address keeper, address router) =
            IEphemeralFactory(msg.sender).context();

        if (block.chainid != intent.chainId) {
            // Wrong-chain recovery: execution is unreachable here by construction, so
            // sweep immediately — no deadline to wait out, nothing to race.
            _refund(intent, sweep, keeper);
        } else if (block.timestamp > intent.deadline) {
            _refund(intent, sweep, keeper);
        } else {
            if (block.timestamp < intent.starttime) {
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

        // Validation is by measured outcome, never by inspecting the route: snapshot,
        // route, assert the delta clears the committed minimum.
        uint256 before = _balance(c.tokenOut, c.recipient);

        _route(router, route, intent.triggers);

        uint256 delta = _balance(c.tokenOut, c.recipient) - before;
        if (delta < c.minAmountOut) {
            revert Insufficient();
        }
    }

    /// The executor's single protocol-facing call. The target is the router the factory
    /// fixed at deployment and the value defers to the native trigger, so a keeper (or a
    /// committed program) chooses calldata only — the executor can never be made to
    /// approve or call anything else. Its own approvals go to the router, exact amounts,
    /// revoked before the outcome is measured: approvals survive selfdestruct into the
    /// next incarnation, so none may outlive the call.
    function _route(address router, bytes memory data, Trigger[] memory triggers) private {
        _approveTriggers(triggers, router, true);
        (bool success, bytes memory ret) = router.call{ value: _value(triggers) }(data);
        if (!success) {
            // Bubble the inner revert reason.
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        _approveTriggers(triggers, router, false);
    }

    function _requireTriggers(Trigger[] memory triggers) private view {
        for (uint256 i; i < triggers.length; ++i) {
            if (_balance(triggers[i].token, address(this)) < triggers[i].minAmount) {
                revert Underfunded();
            }
        }
    }

    function _refund(Intent memory intent, address[] memory sweep, address keeper) private {
        // Fee first, best-effort, so permissionless refunds are self-incentivizing; then
        // committed and keeper-listed tokens to the committed recipient. Native rides the
        // selfdestruct.
        _payFee(intent.keeperFee, keeper, false);
        for (uint256 i; i < intent.triggers.length; ++i) {
            _sweep(intent.triggers[i].token, intent.refundRecipient);
        }
        for (uint256 i; i < sweep.length; ++i) {
            _sweep(sweep[i], intent.refundRecipient);
        }
    }

    function _approveTriggers(Trigger[] memory triggers, address spender, bool grant) private {
        for (uint256 i; i < triggers.length; ++i) {
            address token = triggers[i].token;
            if (token == address(0)) {
                continue; // native travels as call value
            }
            // forceApprove: a reused address can hold a stale allowance from a previous
            // incarnation, which breaks approve-from-nonzero tokens like USDT.
            IERC20(token).forceApprove(spender, grant ? IERC20(token).balanceOf(address(this)) : 0);
        }
    }

    /// Call value for the router: the delivered native balance when a native trigger
    /// exists, zero otherwise — never chosen by the keeper.
    function _value(Trigger[] memory triggers) private view returns (uint256) {
        for (uint256 i; i < triggers.length; ++i) {
            if (triggers[i].token == address(0)) {
                return address(this).balance;
            }
        }
        return 0;
    }

    function _payFee(Fee memory fee, address to, bool strict) private {
        if (fee.amount == 0 || to == address(0)) {
            return;
        }
        bool success;
        if (_balance(fee.token, address(this)) >= fee.amount) {
            success = _transfer(fee.token, to, fee.amount);
        }
        if (strict && !success) {
            revert SendFailed();
        }
    }

    /// Best-effort full-balance transfer: one reverting token must never block an exit.
    function _sweep(address token, address to) private {
        if (token == address(0)) {
            return;
        }
        (bool success, bytes memory ret) = token.staticcall(abi.encodeCall(IERC20.balanceOf, (address(this))));
        if (!success || ret.length < 32) {
            return;
        }
        uint256 balance = abi.decode(ret, (uint256));
        if (balance == 0) {
            return;
        }
        _transfer(token, to, balance);
    }

    /// transfer() tolerant of missing return data; false for false-returning tokens.
    function _transfer(address token, address to, uint256 amount) private returns (bool success) {
        if (token == address(0)) {
            (success,) = to.call{ value: amount }("");
        } else {
            bytes memory ret;
            (success, ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            success = success && (ret.length == 0 || abi.decode(ret, (bool)));
        }
    }

    function _balance(address token, address account) private view returns (uint256) {
        return token == address(0) ? account.balance : IERC20(token).balanceOf(account);
    }
}

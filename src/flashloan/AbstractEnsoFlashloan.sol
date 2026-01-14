// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {
    BalancerV3FlashloanParams,
    DolomiteActions,
    DolomiteFlashloanParams,
    DolomiteTypes,
    IAaveV3Pool,
    IBalancerV3Vault,
    IDolomiteMargin,
    IMorpho,
    IUniswapV3Factory,
    IUniswapV3Pool,
    UniswapV3FlashloanParams
} from "../interfaces/IEnsoFlashloan.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "openzeppelin-contracts/utils/Pausable.sol";

enum LenderProtocol {
    None,
    Morpho,
    AaveV3,
    BalancerV3,
    Dolomite,
    UniswapV3
}

abstract contract AbstractEnsoFlashloan is Ownable, Pausable {
    using SafeERC20 for IERC20;

    error UnsupportedProtocol();
    error NotAuthorized();
    error UnknownLender();
    error IncorrectPaybackAmount(uint256 amount, uint256 requiredAmount);
    error WrongConstrutorParams();

    event LenderRemoved(address indexed lender);

    mapping(address lender => LenderProtocol protocol) public trustedLenders;

    constructor(address[] memory lenders, LenderProtocol[] memory protocols, address owner_) Ownable(owner_) {
        if (lenders.length != protocols.length) {
            revert WrongConstrutorParams();
        }

        for (uint256 i = 0; i < lenders.length; i++) {
            trustedLenders[lenders[i]] = protocols[i];
        }
    }

    function removeLender(address lender) external onlyOwner {
        trustedLenders[lender] = LenderProtocol.None;
        emit LenderRemoved(lender);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function executeFlashloan(
        LenderProtocol protocol,
        bytes calldata protocolFlashloanData,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        external
        payable
        whenNotPaused
    {
        if (protocol == LenderProtocol.Morpho) {
            _executeMorphoFlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.BalancerV3) {
            _executeBalancerV3FlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.AaveV3) {
            _executeAaveV3FlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.Dolomite) {
            _executeDolomiteFlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.UniswapV3) {
            _executeUniswapV3FlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else {
            revert UnsupportedProtocol();
        }
    }

    // --- Flashloan execution ---

    function _executeMorphoFlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IMorpho morpho, address token, uint256 amount) = abi.decode(data, (IMorpho, address, uint256));
        bytes memory morphoCallback = abi.encode(msg.sender, token, accountId, requestId, commands, state);

        morpho.flashLoan(token, amount, morphoCallback);
    }

    function _executeAaveV3FlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IAaveV3Pool pool, address token, uint256 amount) = abi.decode(data, (IAaveV3Pool, address, uint256));
        bytes memory aaveCallback = abi.encode(msg.sender, accountId, requestId, commands, state);

        pool.flashLoanSimple(address(this), token, amount, aaveCallback, 0);
    }

    function _executeBalancerV3FlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IBalancerV3Vault vault, address[] memory tokens, uint256[] memory amounts) =
            abi.decode(data, (IBalancerV3Vault, address[], uint256[]));

        BalancerV3FlashloanParams memory params = BalancerV3FlashloanParams({
            wallet: msg.sender,
            tokens: tokens,
            amounts: amounts,
            accountId: accountId,
            requestId: requestId,
            commands: commands,
            state: state
        });

        vault.unlock(abi.encodeWithSelector(this.onBalancerV3Flashloan.selector, params));
    }

    function _executeDolomiteFlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IDolomiteMargin dolomiteMargin, address token, uint256 amount) =
            abi.decode(data, (IDolomiteMargin, address, uint256));

        uint256 marketId = dolomiteMargin.getMarketIdByTokenAddress(token);

        bytes memory callbackData = abi.encode(
            DolomiteFlashloanParams({
                wallet: msg.sender,
                token: token,
                amount: amount,
                accountId: accountId,
                requestId: requestId,
                commands: commands,
                state: state
            })
        );

        DolomiteTypes.AccountInfo[] memory accounts = new DolomiteTypes.AccountInfo[](1);
        accounts[0] = DolomiteTypes.AccountInfo({ owner: address(this), number: 0 });

        // Actions: Withdraw -> Call -> Deposit
        DolomiteActions.ActionArgs[] memory actions = new DolomiteActions.ActionArgs[](3);

        // Withdraw (borrow)
        actions[0] = DolomiteActions.ActionArgs({
            actionType: DolomiteActions.ActionType.Withdraw,
            accountId: 0,
            amount: DolomiteTypes.AssetAmount({
                sign: false,
                denomination: DolomiteTypes.AssetDenomination.Wei,
                ref: DolomiteTypes.AssetReference.Delta,
                value: amount
            }),
            primaryMarketId: marketId,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });

        // Call (callback)
        actions[1] = DolomiteActions.ActionArgs({
            actionType: DolomiteActions.ActionType.Call,
            accountId: 0,
            amount: DolomiteTypes.AssetAmount({
                sign: false,
                denomination: DolomiteTypes.AssetDenomination.Wei,
                ref: DolomiteTypes.AssetReference.Delta,
                value: 0
            }),
            primaryMarketId: 0,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: callbackData
        });

        // Deposit (repay)
        // this action only happens after the call action is done
        actions[2] = DolomiteActions.ActionArgs({
            actionType: DolomiteActions.ActionType.Deposit,
            accountId: 0,
            amount: DolomiteTypes.AssetAmount({
                sign: true,
                denomination: DolomiteTypes.AssetDenomination.Wei,
                ref: DolomiteTypes.AssetReference.Delta,
                value: amount
            }),
            primaryMarketId: marketId,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });

        IERC20(token).forceApprove(address(dolomiteMargin), amount);
        dolomiteMargin.operate(accounts, actions);
    }

    function _executeUniswapV3FlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IUniswapV3Pool pool, address token0, address token1, uint256 amount0, uint256 amount1) =
            abi.decode(data, (IUniswapV3Pool, address, address, uint256, uint256));

        bytes memory callbackData = abi.encode(
            UniswapV3FlashloanParams({
                wallet: msg.sender,
                token0: token0,
                token1: token1,
                amount0: amount0,
                amount1: amount1,
                accountId: accountId,
                requestId: requestId,
                commands: commands,
                state: state
            })
        );

        pool.flash(address(this), amount0, amount1, callbackData);
    }

    // --- Flashloan callbacks ---

    // LenderProtocol = Morpho
    // Morpho vault calls msg.sender, safe to check only msg.sender
    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        _verifyLender(msg.sender, LenderProtocol.Morpho);

        (
            address wallet,
            IERC20 token,
            bytes32 accountId,
            bytes32 requestId,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (address, IERC20, bytes32, bytes32, bytes32[], bytes[]));

        token.safeTransfer(wallet, amount);
        uint256 balanceBefore = token.balanceOf(address(this));

        executeShortcut(wallet, accountId, requestId, commands, state);

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter < amount + balanceBefore) {
            revert IncorrectPaybackAmount(balanceAfter, amount);
        }

        token.forceApprove(msg.sender, amount);
    }

    // LenderProtocol = BalancerV3
    // BalancerV3 vault calls msg.sender, safe to check only msg.sender
    function onBalancerV3Flashloan(BalancerV3FlashloanParams memory flashloanParams) external {
        _verifyLender(msg.sender, LenderProtocol.BalancerV3);

        uint256[] memory balancesBefore = new uint256[](flashloanParams.tokens.length);
        for (uint256 i = 0; i < flashloanParams.tokens.length; i++) {
            balancesBefore[i] = IERC20(flashloanParams.tokens[i]).balanceOf(address(this));
            IBalancerV3Vault(msg.sender)
                .sendTo(flashloanParams.tokens[i], flashloanParams.wallet, flashloanParams.amounts[i]);
        }

        executeShortcut(
            flashloanParams.wallet,
            flashloanParams.accountId,
            flashloanParams.requestId,
            flashloanParams.commands,
            flashloanParams.state
        );

        for (uint256 i = 0; i < flashloanParams.tokens.length; i++) {
            uint256 amountBorrowed = flashloanParams.amounts[i];
            IERC20(flashloanParams.tokens[i]).safeTransfer(msg.sender, amountBorrowed);
            IBalancerV3Vault(msg.sender).settle(flashloanParams.tokens[i], amountBorrowed);
        }
    }

    // LenderProtocol = AaveV3
    // For Aave V3 both msg.sender and initiator have to be checked, because Aave V3 allows to perform
    // the callback to any address (not strictly limited to caller of flashLoanSimple)
    function executeOperation(
        IERC20 token,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    )
        external
        returns (bool)
    {
        _verifyLender(msg.sender, LenderProtocol.AaveV3);
        if (initiator != address(this)) {
            revert NotAuthorized();
        }

        (address wallet, bytes32 accountId, bytes32 requestId, bytes32[] memory commands, bytes[] memory state) =
            abi.decode(data, (address, bytes32, bytes32, bytes32[], bytes[]));

        token.safeTransfer(wallet, amount);
        uint256 balanceBefore = token.balanceOf(address(this));

        executeShortcut(wallet, accountId, requestId, commands, state);

        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 repaymentAmount = amount + premium;
        if (balanceAfter < repaymentAmount + balanceBefore) {
            revert IncorrectPaybackAmount(balanceAfter, repaymentAmount);
        }

        token.forceApprove(msg.sender, repaymentAmount);

        return true;
    }

    // LenderProtocol = Dolomite
    // For Dolomite, msg.sender is DolomiteMargin and sender param is the initiator.
    // Must verify both (similar to AaveV3's initiator check).
    function callFunction(
        address sender,
        DolomiteTypes.AccountInfo memory, /* accountInfo */
        bytes memory data
    )
        external
    {
        _verifyLender(msg.sender, LenderProtocol.Dolomite);
        if (sender != address(this)) {
            revert NotAuthorized();
        }

        DolomiteFlashloanParams memory params = abi.decode(data, (DolomiteFlashloanParams));

        IERC20 token = IERC20(params.token);
        uint256 amount = params.amount;

        token.safeTransfer(params.wallet, amount);
        uint256 balanceBefore = token.balanceOf(address(this));

        executeShortcut(params.wallet, params.accountId, params.requestId, params.commands, params.state);

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter < amount + balanceBefore) {
            revert IncorrectPaybackAmount(balanceAfter, amount);
        }

        // approval already done in _executeDolomiteFlashLoan, deposit action pulls tokens
    }

    // LenderProtocol = UniswapV3
    // UniswapV3 pool calls msg.sender. We verify the factory is trusted, then validate pool address.
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        UniswapV3FlashloanParams memory params = abi.decode(data, (UniswapV3FlashloanParams));

        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        address factory = pool.factory();
        _verifyLender(factory, LenderProtocol.UniswapV3);

        // NOTE: this might be redundant since we get the factory to verify lender
        uint24 poolFee = pool.fee();
        address expectedPool = IUniswapV3Factory(factory).getPool(params.token0, params.token1, poolFee);
        if (msg.sender != expectedPool) {
            revert UnknownLender();
        }

        if (params.amount0 > 0) {
            IERC20(params.token0).safeTransfer(params.wallet, params.amount0);
        }
        if (params.amount1 > 0) {
            IERC20(params.token1).safeTransfer(params.wallet, params.amount1);
        }

        uint256 balanceBefore0 = params.amount0 > 0 ? IERC20(params.token0).balanceOf(address(this)) : 0;
        uint256 balanceBefore1 = params.amount1 > 0 ? IERC20(params.token1).balanceOf(address(this)) : 0;

        executeShortcut(params.wallet, params.accountId, params.requestId, params.commands, params.state);

        uint256 repay0 = params.amount0 + fee0;
        uint256 repay1 = params.amount1 + fee1;

        if (params.amount0 > 0) {
            uint256 balanceAfter0 = IERC20(params.token0).balanceOf(address(this));
            if (balanceAfter0 < repay0 + balanceBefore0) {
                revert IncorrectPaybackAmount(balanceAfter0, repay0 + balanceBefore0);
            }
        }
        if (params.amount1 > 0) {
            uint256 balanceAfter1 = IERC20(params.token1).balanceOf(address(this));
            if (balanceAfter1 < repay1 + balanceBefore1) {
                revert IncorrectPaybackAmount(balanceAfter1, repay1 + balanceBefore1);
            }
        }

        if (repay0 > 0) {
            IERC20(params.token0).safeTransfer(msg.sender, repay0);
        }
        if (repay1 > 0) {
            IERC20(params.token1).safeTransfer(msg.sender, repay1);
        }
    }

    function _verifyLender(address lender, LenderProtocol expectedProtocol) internal view {
        if (trustedLenders[lender] != expectedProtocol) {
            revert UnknownLender();
        }
    }

    function executeShortcut(
        address wallet,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] memory commands,
        bytes[] memory state
    )
        internal
        virtual;
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import "./EnsoFlashloanInterfaces.sol";

import {VM} from "enso-weiroll/VM.sol";

import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

enum FlashloanProtocols {
    Euler,
    BalancerV2,
    Morpho,
    AaveV3
}

contract EnsoFlashloanShortcuts is VM, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    error UnsupportedFlashloanProtocol();
    error NotSelf();
    error NotAuthorized();

    function flashLoan(
        FlashloanProtocols protocol,
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] calldata state
    ) external {
        if (protocol == FlashloanProtocols.Euler) {
            _executeEulerFlashLoan(excessReceiver, data, commands, state);
        } else if (protocol == FlashloanProtocols.BalancerV2) {
            _executeBalancerV2FlashLoan(excessReceiver, data, commands, state);
        } else if (protocol == FlashloanProtocols.Morpho) {
            _executeMorphoFlashLoan(excessReceiver, data, commands, state);
        } else if (protocol == FlashloanProtocols.AaveV3) {
            _executeAaveV3FlashLoan(excessReceiver, data, commands, state);
        } else {
            revert UnsupportedFlashloanProtocol();
        }
    }

    function execute(bytes32[] calldata commands, bytes[] memory state) public {
        require(msg.sender == address(this), NotSelf());
        _execute(commands, state);
    }

    // --- Flashloan execution ---

    function _executeEulerFlashLoan(
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] calldata state
    ) private {
        (IEVault EulerVault, address token, uint256 amount) = abi.decode(
            data,
            (IEVault, address, uint256)
        );

        bytes memory eulerCallback = abi.encode(
            amount,
            token,
            excessReceiver,
            commands,
            state
        );

        EulerVault.flashLoan(amount, eulerCallback);
    }

    function _executeBalancerV2FlashLoan(
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] calldata state
    ) private {
        (
            IBalancerV2Vault Vault,
            address[] memory tokens,
            uint256[] memory amounts
        ) = abi.decode(data, (IBalancerV2Vault, address[], uint256[]));

        bytes memory balancerV2Callback = abi.encode(
            excessReceiver,
            commands,
            state
        );

        Vault.flashLoan(address(this), tokens, amounts, balancerV2Callback);
    }

    function _executeMorphoFlashLoan(
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] calldata state
    ) private {
        (IMorpho morpho, address token, uint256 amount) = abi.decode(
            data,
            (IMorpho, address, uint256)
        );
        bytes memory morphoCallback = abi.encode(
            token,
            excessReceiver,
            commands,
            state
        );

        morpho.flashLoan(token, amount, morphoCallback);
    }

    function _executeAaveV3FlashLoan(
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] calldata state
    ) private {
        (IAaveV3Pool Pool, address token, uint256 amount) = abi.decode(
            data,
            (IAaveV3Pool, address, uint256)
        );

        bytes memory aaveCallback = abi.encode(excessReceiver, commands, state);

        Pool.flashLoanSimple(address(this), token, amount, aaveCallback, 0);
    }

    // --- Flashloan callbacks ---

    // Euler
    function onFlashLoan(bytes calldata data) external {
        (
            uint256 amount,
            IERC20 token,
            address excessReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (uint256, IERC20, address, bytes32[], bytes[]));

        this.execute(commands, state);

        _returnExcessAssets(token, amount, excessReceiver);

        token.safeTransfer(msg.sender, amount);
    }

    // BalancerV2
    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata data
    ) external {
        (
            address excessReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (address, bytes32[], bytes[]));

        this.execute(commands, state);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 repayAmount = amounts[i] + feeAmounts[i];
            _returnExcessAssets(tokens[i], repayAmount, excessReceiver);
            tokens[i].safeTransfer(msg.sender, repayAmount);
        }
    }

    // Morpho
    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        (
            IERC20 token,
            address excessReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (IERC20, address, bytes32[], bytes[]));

        this.execute(commands, state);

        _returnExcessAssets(token, amount, excessReceiver);

        token.forceApprove(msg.sender, amount);
    }

    // Aave V3
    function executeOperation(
        IERC20 asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    ) external returns (bool) {
        require(initiator == address(this), NotAuthorized());
        (
            address excessReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (address, bytes32[], bytes[]));

        this.execute(commands, state);

        uint256 repayAmount = amount + premium;
        _returnExcessAssets(asset, repayAmount, excessReceiver);
        asset.forceApprove(msg.sender, repayAmount);

        return true;
    }

    function _returnExcessAssets(
        IERC20 token,
        uint256 flashloanAmount,
        address receiver
    ) private {
        uint256 flashloanAssetBalance = token.balanceOf(address(this));
        if (flashloanAssetBalance > flashloanAmount) {
            uint256 excessAmount;
            unchecked {
                excessAmount = flashloanAssetBalance - flashloanAmount;
            }
            token.safeTransfer(receiver, excessAmount);
        }
    }

    receive() external payable {}
}

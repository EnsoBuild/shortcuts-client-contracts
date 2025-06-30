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
    Morpho
}

contract EnsoFlashloanShortcuts is VM, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    IMorpho public immutable MORPHO;
    IEulerGenericFactory public immutable EULER_FACTORY;

    event ShortcutExecuted(bytes32 accountId, bytes32 requestId);

    error UnsupportedFlashloanProtocol();
    error NotSelf();
    error NotAuthorized();

    constructor(IMorpho _morpho, IEulerGenericFactory _eulerFactory) {
        MORPHO = _morpho;
        EULER_FACTORY = _eulerFactory;
    }

    function flashLoan(
        FlashloanProtocols protocol,
        address excessReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] memory state
    ) external {
        if (protocol == FlashloanProtocols.Euler) {
            (address token, uint256 amount, IEVault EulerVault) = abi.decode(
                data,
                (address, uint256, IEVault)
            );

            bytes memory eulerCallback = abi.encode(
                amount,
                token,
                excessReceiver,
                commands,
                state
            );

            EulerVault.flashLoan(amount, eulerCallback);
        } else if (protocol == FlashloanProtocols.BalancerV2) {
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
        } else if (protocol == FlashloanProtocols.Morpho) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            bytes memory morphoCallback = abi.encode(
                token,
                excessReceiver,
                commands,
                state
            );

            MORPHO.flashLoan(token, amount, morphoCallback);
        } else {
            revert UnsupportedFlashloanProtocol();
        }
    }

    function execute(bytes32[] calldata commands, bytes[] memory state) public {
        require(msg.sender == address(this), NotSelf());
        _execute(commands, state);
    }

    // --- Flashloan callbacks ---

    // Euler
    function onFlashLoan(bytes calldata data) external {
        require(EULER_FACTORY.isProxy(msg.sender), NotAuthorized());
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
        require(msg.sender == address(MORPHO), NotAuthorized());
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

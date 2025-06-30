// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {IRouter, IERC3156FlashBorrower, IEulerGenericFactory, IEVault, IMorpho} from "./EnsoFlashloanInterfaces.sol";

import {VM} from "enso-weiroll/VM.sol";

import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

enum FlashloanProtocols {
    Morpho,
    Euler
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
        address excessFlashloanReceiver,
        bytes calldata data,
        bytes32[] calldata commands,
        bytes[] memory state
    ) external {
        if (protocol == FlashloanProtocols.Morpho) {
            (address token, uint256 amount) = abi.decode(
                data,
                (address, uint256)
            );
            bytes memory morphoCallback = abi.encode(
                token,
                excessFlashloanReceiver,
                commands,
                state
            );

            MORPHO.flashLoan(token, amount, morphoCallback);
        } else if (protocol == FlashloanProtocols.Euler) {
            (address token, uint256 amount, IEVault eulerVault) = abi.decode(
                data,
                (address, uint256, IEVault)
            );

            bytes memory eulerCallback = abi.encode(
                amount,
                token,
                excessFlashloanReceiver,
                commands,
                state
            );

            eulerVault.flashLoan(amount, eulerCallback);
        } else {
            revert UnsupportedFlashloanProtocol();
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(MORPHO), NotAuthorized());
        (
            IERC20 token,
            address excessFlashloanReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (IERC20, address, bytes32[], bytes[]));

        this.execute(commands, state);
        _returnExcessAssets(token, amount, excessFlashloanReceiver);

        token.forceApprove(msg.sender, amount);
    }

    function onFlashLoan(bytes calldata data) external {
        require(EULER_FACTORY.isProxy(msg.sender), NotAuthorized());
        (
            uint256 amount,
            IERC20 token,
            address excessFlashloanReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (uint256, IERC20, address, bytes32[], bytes[]));

        this.execute(commands, state);
        _returnExcessAssets(token, amount, excessFlashloanReceiver);

        token.safeTransfer(msg.sender, amount);
    }

    function execute(bytes32[] calldata commands, bytes[] memory state) public {
        require(msg.sender == address(this), NotSelf());
        _execute(commands, state);
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

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {IRouter, IERC3156FlashBorrower, IEulerFlashloan, IMorpho} from "./EnsoFlashloanInterfaces.sol";

import {VM} from "enso-weiroll/VM.sol";

import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

enum FlashloanProtocols {
    Morpho
}

contract EnsoFlashloanShortcuts is VM, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    IMorpho public immutable morpho;

    event ShortcutExecuted(bytes32 accountId, bytes32 requestId);

    error ProtocolNotSupported();
    error NotSelf();
    error OnlyProtocol();

    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
    }

    function flashLoan(
        FlashloanProtocols protocol,
        address token,
        uint256 amount,
        address excessFlashloanReceiver,
        bytes32[] calldata commands,
        bytes[] memory state
    ) external {
        if (protocol == FlashloanProtocols.Morpho) {
            bytes memory morphoCallback = abi.encode(
                token,
                excessFlashloanReceiver,
                commands,
                state
            );

            morpho.flashLoan(token, amount, morphoCallback);
        } else {
            revert ProtocolNotSupported();
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(morpho), OnlyProtocol());
        (
            IERC20 token,
            address excessFlashloanReceiver,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (IERC20, address, bytes32[], bytes[]));

        this.execute(commands, state);

        // At this stage we expect loaned asset to be inside the contract.
        // If at this point token.balanceOf(this) > amount, we send excess amount to receiver
        uint256 flashloanedAssetBalance = token.balanceOf(address(this));
        if (flashloanedAssetBalance > amount) {
            uint256 excessAmount;
            unchecked {
                excessAmount = flashloanedAssetBalance - amount;
            }
            token.safeTransfer(excessFlashloanReceiver, excessAmount);
        }

        token.forceApprove(msg.sender, amount);
    }

    function execute(bytes32[] calldata commands, bytes[] memory state) public {
        require(msg.sender == address(this), NotSelf());
        _execute(commands, state);
    }

    receive() external payable {}
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import {IRouter, IERC3156FlashBorrower, IEulerFlashloan, IMorpho} from "./EnsoFlashloanInterfaces.sol";
import {IERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

enum FlashloanProtocols {
    Euler,
    Morpho
}

// WARN: This is work in progress.
// Currently this approach only supports single flashloaned asset
// to be routed through router.

contract EnsoFlashloan is IERC3156FlashBorrower {
    using SafeERC20 for IERC20;

    bytes32 public constant ERC3156_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    IRouter public immutable router;
    IEulerFlashloan public immutable eulerFlashloan;
    IMorpho public immutable morpho;

    error ProtocolNotSupported();

    constructor(address _router, address _eulerFlashloan, address _morpho) {
        router = IRouter(_router);
        eulerFlashloan = IEulerFlashloan(_eulerFlashloan);
        morpho = IMorpho(_morpho);
    }

    function flashLoan(
        FlashloanProtocols protocol,
        bytes calldata data
    ) external {
        if (protocol == FlashloanProtocols.Euler) {
            (address token, uint256 amount, bytes memory routerData) = abi
                .decode(data, (address, uint256, bytes));

            eulerFlashloan.flashLoan(address(this), token, amount, routerData);
        } else if (protocol == FlashloanProtocols.Morpho) {
            (
                address token,
                uint256 amount,
                bytes memory shortcutAndTokenData
            ) = abi.decode(data, (address, uint256, bytes));

            morpho.flashLoan(token, amount, shortcutAndTokenData);
        } else {
            revert ProtocolNotSupported();
        }
    }

    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        require(msg.sender == address(morpho), "not allowed");
        (address token, bytes memory shortcutData) = abi.decode(
            data,
            (address, bytes)
        );

        _executeRouter(token, amount, shortcutData);

        // In Morpho flashloan tokens have to be approved,
        // tokens will be pulled out by the flashloan contract
        IERC20(token).forceApprove(msg.sender, amount);
    }

    // ERC3156 callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256,
        bytes calldata data
    ) external returns (bytes32) {
        require(
            msg.sender == address(eulerFlashloan) && initiator == address(this),
            "not allowed"
        );

        _executeRouter(token, amount, data);

        // In ERC3156 tokens are not required to be sent back,
        // tokens will be pulled out by the flashloan contract
        IERC20(token).forceApprove(msg.sender, amount);

        return ERC3156_SUCCESS;
    }

    function _executeRouter(
        address token,
        uint256 amount,
        bytes memory shortcutData
    ) internal {
        // Only ERC20s are possible
        IRouter.Token memory tokenIn = IRouter.Token(
            IRouter.TokenType.ERC20,
            abi.encode(token, amount)
        );
        IERC20(token).forceApprove(address(router), amount);

        router.routeSingle(tokenIn, shortcutData);
    }
}

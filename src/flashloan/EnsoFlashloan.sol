// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IEnsoWalletV2 } from "../interfaces/IEnsoWalletV2.sol";
import { IAaveV3Pool, IBalancerV2Vault, IERC3156FlashBorrower, IEVault, IMorpho } from "./EnsoFlashloanInterfaces.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

enum LenderProtocol {
    None,
    Euler,
    Morpho,
    AaveV3
}

contract EnsoFlashloan {
    using SafeERC20 for IERC20;

    error UnsupportedProtocol();
    error NotAuthorized();
    error UnknownLender();
    error IncorrectPaybackAmount();
    error WrongConstrutorParams();

    mapping(address lender => LenderProtocol protocol) private _trustedLenders;

    constructor(address[] memory lenders, LenderProtocol[] memory protocols) {
        if (lenders.length != protocols.length) {
            revert WrongConstrutorParams();
        }

        for (uint256 i = 0; i < lenders.length; i++) {
            _trustedLenders[lenders[i]] = protocols[i];
        }
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
    {
        if (protocol == LenderProtocol.Euler) {
            _executeEulerFlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.Morpho) {
            _executeMorphoFlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else if (protocol == LenderProtocol.AaveV3) {
            _executeAaveV3FlashLoan(protocolFlashloanData, accountId, requestId, commands, state);
        } else {
            revert UnsupportedProtocol();
        }
    }

    // --- Flashloan execution ---

    function _executeEulerFlashLoan(
        bytes calldata data,
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        private
    {
        (IEVault EulerVault, address token, uint256 amount) = abi.decode(data, (IEVault, address, uint256));
        bytes memory eulerCallback = abi.encode(msg.sender, amount, token, accountId, requestId, commands, state);

        EulerVault.flashLoan(amount, eulerCallback);
    }

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
        (IAaveV3Pool Pool, address token, uint256 amount) = abi.decode(data, (IAaveV3Pool, address, uint256));
        bytes memory aaveCallback = abi.encode(msg.sender, accountId, requestId, commands, state);

        Pool.flashLoanSimple(address(this), token, amount, aaveCallback, 0);
    }

    // --- Flashloan callbacks ---

    // Euler
    // function onFlashLoan(bytes calldata data) external {
    //     (uint256 amount, IERC20 token, address excessReceiver, bytes32[] memory commands, bytes[] memory state) =
    //         abi.decode(data, (uint256, IERC20, address, bytes32[], bytes[]));
    //
    //     // this.execute(commands, state);
    //     //
    //     // _returnExcessAssets(token, amount, excessReceiver);
    //     //
    //     // token.safeTransfer(msg.sender, amount);
    // }

    // Morpho
    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external {
        _verifyLender(msg.sender, LenderProtocol.Morpho);

        (
            IEnsoWalletV2 wallet,
            IERC20 token,
            bytes32 accountId,
            bytes32 requestId,
            bytes32[] memory commands,
            bytes[] memory state
        ) = abi.decode(data, (IEnsoWalletV2, IERC20, bytes32, bytes32, bytes32[], bytes[]));

        token.safeTransfer(address(wallet), amount);
        uint256 balanceBefore = token.balanceOf(address(this));

        wallet.executeShortcut(accountId, requestId, commands, state);

        if (token.balanceOf(address(this)) != amount + balanceBefore) {
            revert IncorrectPaybackAmount();
        }

        token.approve(msg.sender, amount);
    }

    function _verifyLender(address lender, LenderProtocol expectedProtocol) internal view {
        if (_trustedLenders[lender] != expectedProtocol) {
            revert UnknownLender();
        }
    }

    // Aave V3
    // function executeOperation(
    //     IERC20 asset,
    //     uint256 amount,
    //     uint256 premium,
    //     address initiator,
    //     bytes calldata data
    // )
    //     external
    //     returns (bool)
    // {
    //     require(initiator == address(this), NotAuthorized());
    //     (address excessReceiver, bytes32[] memory commands, bytes[] memory state) =
    //         abi.decode(data, (address, bytes32[], bytes[]));
    //
    //     // this.execute(commands, state);
    //     //
    //     // uint256 repayAmount = amount + premium;
    //     // _returnExcessAssets(asset, repayAmount, excessReceiver);
    //     // asset.forceApprove(msg.sender, repayAmount);
    //
    //     return true;
    // }

    receive() external payable { }
}

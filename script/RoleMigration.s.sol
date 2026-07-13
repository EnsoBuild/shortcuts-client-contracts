// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { LayerZeroReceiver } from "../src/bridge/LayerZeroReceiver.sol";
import { ChainOwner } from "../src/libraries/ChainOwner.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { SignaturePaymaster } from "../src/paymaster/SignaturePaymaster.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Migrates roles away from the deployer EOA on the current chain:
///   1. LayerZeroReceiver: adds OFT_REGISTRAR as registrar (if not set) and removes the deployer
///   2. SignaturePaymaster: enables PAYMASTER_SIGNER (if not set) and disables OLD_SIGNER
///   3. Transfers ownership of all deployer-owned contracts to the per-chain owner in _newOwnerFor()
///      (SignaturePaymaster and EnsoCCIPReceiver are Ownable2Step — the new owner must call acceptOwnership)
///   4. Sends 25% of the deployer's balance to OFT_REGISTRAR and 25% to RECIPIENT
///      (native asset, except on Tempo where USDC.e is distributed instead)
///
/// Contract addresses are discovered from broadcast/<Deployer>.s.sol/<chainid>/run-latest.json.
/// Overrides: LZ_RECEIVER, PAYMASTER, CCIP_RECEIVER env vars.
/// Required env: PRIVATE_KEY (must be the deployer key).
contract RoleMigration is Script {
    address constant DEPLOYER = 0x826e0BB2276271eFdF2a500597f37b94f6c153bA;
    address constant OFT_REGISTRAR = 0xee1f0029E03f4fA36895B9C117F0eA669feC9126;
    address constant PAYMASTER_SIGNER = 0x89B3c70f6dF4Fc6Ba0613de208c9da5132b8ecc2;
    address constant OLD_SIGNER = 0xFE503EE14863F6aCEE10BCdc66aC5e2301b3A946;
    address constant RECIPIENT = 0xAf873a7Ab95090f2B01Fc38f492268c648C9E555;
    // Tempo has no native asset — funding is distributed in USDC.e there instead
    address constant USDCE = 0x20C000000000000000000000b9537d11c60E8b50;
    // Deterministic CREATE2 address (salt "SignaturePaymaster"), same on every chain it was deployed to
    address constant PAYMASTER = 0xfa66d86a5Efc7632070b1F0b1C639C69a7E7D8C5;

    function run() public {
        bool prevRun;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(vm.addr(deployerPrivateKey) == DEPLOYER, "PRIVATE_KEY does not match the deployer address");
        // ownerFor reverts on chains with no configured owner
        address newOwner = ChainOwner.ownerFor(block.chainid);
        require(newOwner != DEPLOYER, "new owner must not be the deployer");

        address lzReceiver = vm.envOr("LZ_RECEIVER", _deploymentAddress("LayerZeroDeployer.s.sol", "lzReceiver"));
        address paymaster = vm.envOr("PAYMASTER", PAYMASTER);
        address ccipReceiver =
            vm.envOr("CCIP_RECEIVER", _deploymentAddress("EnsoCCIPReceiverDeployer.s.sol", "ensoCcipReceiver"));
        address routerAdapter = _deploymentAddress("FlashloanAdapterDeployer.s.sol", "routerAdapter");
        address safeAdapter = _deploymentAddress("FlashloanAdapterDeployer.s.sol", "safeAdapter");
        address walletAdapter = _deploymentAddress("FlashloanAdapterDeployer.s.sol", "walletAdapter");

        vm.startBroadcast(deployerPrivateKey);

        // 1. LayerZeroReceiver: swap OFT registrar
        if (_isLive(lzReceiver)) {
            LayerZeroReceiver receiver = LayerZeroReceiver(payable(lzReceiver));
            if (receiver.owner() == DEPLOYER) {
                if (!receiver.validRegistrar(OFT_REGISTRAR)) {
                    receiver.setRegistrar(OFT_REGISTRAR);
                    console.log("LayerZeroReceiver: registrar added", OFT_REGISTRAR);
                }
                if (receiver.validRegistrar(DEPLOYER)) {
                    receiver.removeRegistrar(DEPLOYER);
                    console.log("LayerZeroReceiver: deployer removed as registrar");
                }
            } else {
                prevRun = true;
                console.log("LayerZeroReceiver: owner is not the deployer, skipping registrar swap", receiver.owner());
            }
        } else {
            console.log("LayerZeroReceiver: not deployed on chain", block.chainid);
        }

        // 2. SignaturePaymaster: swap signer
        if (_isLive(paymaster)) {
            SignaturePaymaster pm = SignaturePaymaster(paymaster);
            if (pm.owner() == DEPLOYER) {
                if (!pm.validSigners(PAYMASTER_SIGNER)) {
                    pm.setSigner(PAYMASTER_SIGNER, true);
                    console.log("SignaturePaymaster: signer enabled", PAYMASTER_SIGNER);
                }
                if (pm.validSigners(OLD_SIGNER)) {
                    pm.setSigner(OLD_SIGNER, false);
                    console.log("SignaturePaymaster: old signer disabled", OLD_SIGNER);
                }
            } else {
                console.log("SignaturePaymaster: owner is not the deployer, skipping signer swap", pm.owner());
            }
        } else {
            console.log("SignaturePaymaster: not deployed on chain", block.chainid);
        }

        // 3. Ownership transfers — must run after the onlyOwner calls above
        _transferOwnership("LayerZeroReceiver", lzReceiver, newOwner, false);
        _transferOwnership("SignaturePaymaster", paymaster, newOwner, true);
        _transferOwnership("EnsoCCIPReceiver", ccipReceiver, newOwner, true);
        _transferOwnership("EnsoRouterFlashloanAdapter", routerAdapter, newOwner, false);
        _transferOwnership("EnsoSafeFlashloanAdapter", safeAdapter, newOwner, false);
        _transferOwnership("EnsoWalletFlashloanAdapter", walletAdapter, newOwner, false);

        // 4. Distribute the deployer's balance: 25% to the OFT registrar, 25% to RECIPIENT
        // (native asset, except on Tempo where USDC.e is used)
        if (!prevRun) {
            if (block.chainid == ChainId.TEMPO) {
                uint256 balance = IERC20(USDCE).balanceOf(DEPLOYER);
                if (balance > 0) {
                    uint256 quarter = balance / 4;
                    require(IERC20(USDCE).transfer(OFT_REGISTRAR, quarter), "USDC.e transfer to OFT registrar failed");
                    console.log("Funded OFT registrar with USDC.e", quarter);

                    require(IERC20(USDCE).transfer(RECIPIENT, quarter), "USDC.e transfer to recipient failed");
                    console.log("Funded recipient with USDC.e", quarter);
                }
            } else {
                uint256 balance = DEPLOYER.balance;
                if (balance > 0) {
                    uint256 quarter = balance / 4;
                    (bool success,) = OFT_REGISTRAR.call{ value: quarter }("");
                    require(success, "funding transfer to OFT registrar failed");
                    console.log("Funded OFT registrar with", quarter);

                    (success,) = RECIPIENT.call{ value: quarter }("");
                    require(success, "funding transfer to recipient failed");
                    console.log("Funded recipient with", quarter);
                }
            }
        }

        vm.stopBroadcast();
    }

    function _transferOwnership(string memory label, address target, address newOwner, bool twoStep) internal {
        if (!_isLive(target)) {
            return;
        }
        address currentOwner = Ownable(target).owner();
        if (currentOwner == newOwner) {
            console.log(label, "already owned by new owner");
            return;
        }
        if (twoStep && Ownable2Step(target).pendingOwner() == newOwner) {
            console.log(label, "ownership transfer already pending acceptance");
            return;
        }
        if (currentOwner != DEPLOYER) {
            console.log(label, "owner is not the deployer, skipping transfer:", currentOwner);
            return;
        }
        Ownable(target).transferOwnership(newOwner);
        if (twoStep) {
            console.log(label, "ownership transfer initiated, new owner must call acceptOwnership()");
        } else {
            console.log(label, "ownership transferred");
        }
    }

    function _deploymentAddress(string memory deployScript, string memory returnKey) internal view returns (address) {
        string memory path = string.concat(
            vm.projectRoot(), "/broadcast/", deployScript, "/", vm.toString(block.chainid), "/run-latest.json"
        );
        if (!vm.exists(path)) {
            return address(0);
        }
        string memory json = vm.readFile(path);
        string memory jsonKey = string.concat(".returns.", returnKey, ".value");
        if (!vm.keyExistsJson(json, jsonKey)) {
            return address(0);
        }
        return vm.parseJsonAddress(json, jsonKey);
    }

    function _isLive(address target) internal view returns (bool) {
        return target != address(0) && target.code.length > 0;
    }
}

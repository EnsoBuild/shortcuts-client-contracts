// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoCCIPReceiver } from "../src/bridge/EnsoCCIPReceiver.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { Script } from "forge-std/Script.sol";

contract EnsoCCIPReceiverDeployer is Script {
    error EnsoRouterIsNotSet();
    error CCIPRouterIsNotSet();
    error OwnerIsNotSet();
    error UnsupportedChainId(uint256 chainId);

    function run() public returns (address ensoCcipReceiver, address owner, address ccipRouter, address ensoRouter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;

        // TODO: set owner address
        owner = 0x6AA68C46eD86161eB318b1396F7b79E386e88676;
        if (chainId == ChainId.ETHEREUM) {
            ccipRouter = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.OPTIMISM) {
            ccipRouter = 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.BINANCE) {
            ccipRouter = 0x34B03Cb9086d7D758AC55af71584F81A598759FE;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.GNOSIS) {
            ccipRouter = 0x4aAD6071085df840abD9Baf1697d5D5992bDadce;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.UNICHAIN) {
            ccipRouter = 0x68891f5F96695ECd7dEdBE2289D1b73426ae7864;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.POLYGON) {
            ccipRouter = 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.MONAD) {
            ccipRouter = 0x33566fE5976AAa420F3d5C64996641Fc3858CaDB;
            ensoRouter = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // NOTE: different router for Monad
        } else if (chainId == ChainId.SONIC) {
            ccipRouter = 0xB4e1Ff7882474BB93042be9AD5E1fA387949B860;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.ZKSYNC) {
            ccipRouter = 0x748Fd769d81F5D94752bf8B0875E9301d0ba71bB;
            ensoRouter = 0x1BD8CefD703CF6b8fF886AD2E32653C32bc62b5C; // NOTE: different router for zkSync
        } else if (chainId == ChainId.WORLD) {
            ccipRouter = 0x5fd9E4986187c56826A3064954Cfa2Cf250cfA0f;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.HYPER) {
            ccipRouter = 0x13b3332b66389B1467CA6eBd6fa79775CCeF65ec;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.BASE) {
            ccipRouter = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.PLASMA) {
            ccipRouter = 0xcDca5D374e46A6DDDab50bD2D9acB8c796eC35C3;
            ensoRouter = 0xCfBAa9Cfce952Ca4F4069874fF1Df8c05e37a3c7; // NOTE: different router for Plasma
        } else if (chainId == ChainId.ARBITRUM) {
            ccipRouter = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.AVALANCHE) {
            ccipRouter = 0xF4c7E640EdA248ef95972845a62bdC74237805dB;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.INK) {
            ccipRouter = 0xca7c90A52B44E301AC01Cb5EB99b2fD99339433A;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.LINEA) {
            ccipRouter = 0x549FEB73F2348F6cD99b9fc8c69252034897f06C;
            ensoRouter = 0xA146d46823f3F594B785200102Be5385CAfCE9B5; // NOTE: different router for Linea
        } else if (chainId == ChainId.BERACHAIN) {
            ccipRouter = 0x71a275704c283486fBa26dad3dd0DB78804426eF;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else if (chainId == ChainId.PLUME) {
            ccipRouter = 0x5C4f4622AD0EC4a47e04840db7E9EcA8354109af;
            ensoRouter = 0x3067BDBa0e6628497d527bEF511c22DA8b32cA3F; // NOTE: different router for Plume
        } else if (chainId == ChainId.KATANA) {
            ccipRouter = 0x7c19b79D2a054114Ab36ad758A36e92376e267DA;
            ensoRouter = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
        } else {
            revert UnsupportedChainId(chainId);
        }

        if (owner == address(0)) {
            revert OwnerIsNotSet();
        }
        if (ccipRouter == address(0)) {
            revert CCIPRouterIsNotSet();
        }
        if (ensoRouter == address(0)) {
            revert EnsoRouterIsNotSet();
        }

        vm.startBroadcast(deployerPrivateKey);

        ensoCcipReceiver = address(new EnsoCCIPReceiver{ salt: "EnsoCCIPReceiver" }(owner, ccipRouter, ensoRouter));

        vm.stopBroadcast();
    }
}

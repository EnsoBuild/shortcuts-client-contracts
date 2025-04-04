#!/bin/bash
# e.g. deploy.sh FullDeployer.s.sol ethereum broadcast etherscan

args=("$@")

script=${args[0]}
network=${args[1]}
broadcast=${args[2]}
verifier=${args[3]}
network_upper="${network^^}"
rpc="${network_upper}_RPC_URL"
blockscan_key="${network_upper}_BLOCKSCAN_KEY"

source .env

params=()
if [[ $network_upper == "ZKSNYC" ]]; then
    params+=(--zksync)
    params+=(--slow)
fi
if [ $broadcast == "broadcast" ]; then
    params+=(--broadcast)
    if [ -n "$verifier" ]; then
        params+=(--verify)
        params+=(--verifier "${verifier}")
        if [ $verifier == "etherscan" ]; then
            if [ $network_upper == "BERACHAIN" ]; then
                params+=(--verifier-url "https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan")
                params+=(--etherscan-api-key "verifyContract")
            elif [ -n "$blockscan_key" ]; then
                params+=(--etherscan-api-key ${!blockscan_key})
            fi
        elif [ $verifier == "blockscout" ]; then
            if [ $network_upper == "INK"]; then
                params+=(--verifier-url "https://explorer.inkonchain.com/api")
            else
                params+=(--verifier-url "https://${network}.blockscout.com/api")
            fi
        fi
    fi
    params+=(-vvvv)
fi

set -x
forge script script/${script} --private-key $PRIVATE_KEY --rpc-url ${!rpc} "${params[@]}"

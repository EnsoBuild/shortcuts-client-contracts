#!/bin/bash
# e.g. deploy.sh FullDeployer.s.sol ethereum broadcast etherscan

args=("$@")

script=${args[0]}
network=${args[1]}
broadcast=${args[2]}
verifier=${args[3]}
network_upper="${network^^}"
rpc="${network_upper}_RPC_URL"
#blockscan_key="${network_upper}_BLOCKSCAN_KEY"
blockscan_key="ETHEREUM_BLOCKSCAN_KEY"

source .env
params=()
if [ $network_upper == "ZKSYNC" ]; then
    params+=(--zksync)
    params+=(--slow)
fi
if [[ $network_upper == "LINEA" ]]; then
    params+=(--evm-version "london")
fi
if [[ $network_upper == "POLYGON" ]]; then
    params+=(--gas-estimate-multiplier 300)
fi
if [ $broadcast == "broadcast" ]; then
    params+=(--broadcast)
    if [ -n "$verifier" ]; then
        params+=(--verify)
        if [ $verifier == "routescan" ]; then
            params+=(--verifier custom)
            if [ $network_upper == "BERACHAIN" ]; then
                chain_id=80094
            elif [ $network_upper == "PLASMA" ]; then
                chain_id=9745
            else
                printf '%s\n' "Invalid routescan network" >&2
                exit 1
            fi
            params+=(--verifier-url "https://api.routescan.io/v2/network/mainnet/evm/${chain_id}/etherscan")
            params+=(--etherscan-api-key "verifyContract")
        else
            params+=(--verifier "${verifier}")
            if [ $verifier == "etherscan" ]; then
                params+=(--etherscan-api-key ${!blockscan_key})
            elif [ $verifier == "blockscout" ]; then
                if [ $network_upper == "INK"]; then
                    params+=(--verifier-url "https://explorer.inkonchain.com/api")
                elif [ $network_upper == "PLUME"]; then
                    params+=(--verifier-url "https://explorer.plume.org/api")
                elif [ $network_upper == "KATANA"]; then
                    params+=(--verifier-url "https://explorer.katanarpc.com/api")
                else
                    params+=(--verifier-url "https://${network}.blockscout.com/api")
                fi
            fi
        fi
    fi
    params+=(-vvvv)
fi

set -x
forge script script/${script} --private-key $PRIVATE_KEY --rpc-url ${!rpc} "${params[@]}"

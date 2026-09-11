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

# Signer comes from an encrypted Foundry keystore, never a raw key in .env.
# Create once: cast wallet import enso-deployer --interactive
# Override the account name via DEPLOYER_ACCOUNT if needed.
account="${DEPLOYER_ACCOUNT:-enso-deployer}"

params=()
if [[ $network_upper == "ZKSYNC" ]]; then
    params+=(--zksync)
    params+=(--slow)
fi
if [[ $network_upper == "POLYGON" ]]; then
    params+=(--gas-estimate-multiplier 300)
fi
if [[ $network_upper == "TEMPO" ]]; then
    params+=(--tempo.fee-token "0x20c000000000000000000000b9537d11c60e8b50")
fi
if [[ $broadcast == "broadcast" ]]; then
    params+=(--broadcast)
    if [[ -n "$verifier" ]]; then
        params+=(--verify)
        if [[ $verifier == "routescan" ]]; then
            params+=(--verifier custom)
            if [[ $network_upper == "BERACHAIN" ]]; then
                chain_id=80094
            elif [[ $network_upper == "MONAD" ]]; then
                chain_id=143
            elif [[ $network_upper == "PLASMA" ]]; then
                chain_id=9745
            else
                printf '%s\n' "Invalid routescan network" >&2
                exit 1
            fi
            params+=(--verifier-url "https://api.routescan.io/v2/network/mainnet/evm/${chain_id}/etherscan")
            params+=(--etherscan-api-key "verifyContract")
        elif [[ $verifier == "tempo" ]]; then
            params+=(--verifier-url "https://contracts.tempo.xyz/")
        else
            params+=(--verifier "${verifier}")
            if [[ $verifier == "etherscan" ]]; then
                params+=(--etherscan-api-key ${!blockscan_key})
            elif [[ $verifier == "blockscout" ]]; then
                if [[ $network_upper == "INK" ]]; then
                    params+=(--verifier-url "https://explorer.inkonchain.com/api")
                elif [[ $network_upper == "PLUME" ]]; then
                    params+=(--verifier-url "https://explorer.plume.org/api")
                elif [[ $network_upper == "KATANA" ]]; then
                    params+=(--verifier-url "https://explorer.katanarpc.com/api")
                elif [[ $network_upper == "ETHERLINK" ]]; then
                    params+=(--verifier-url "https://explorer.etherlink.com/api")
                elif [[ $network_upper == "ROBINHOOD" ]]; then
                    params+=(--verifier-url "https://robinhoodchain.blockscout.com/api")
                elif [[ $network_upper == "ARC" ]]; then
                    # TODO(ENSO-469): verifier pending, the explorer is permissioned
                    printf '%s\n' "Arc verification is not configured yet" >&2
                    exit 1
                else
                    params+=(--verifier-url "https://${network}.blockscout.com/api")
                fi
            fi
        fi
    fi
    params+=(-vvvv)
fi

{ set +x; } 2>/dev/null

# Signing config. --account makes forge unlock the keystore to resolve the
# signer for vm.startBroadcast(), so it prompts for the password even without
# --broadcast and dies with "os error 6" when there is no tty.
# For dry runs, set DEPLOYER_ADDRESS to simulate with --sender: an address alone
# needs no unlock. Broadcasting always uses the keystore.
signer=(--account "$account")
if [[ $broadcast != "broadcast" && -n "$DEPLOYER_ADDRESS" ]]; then
    signer=(--sender "$DEPLOYER_ADDRESS")
fi

forge script "script/${script}" --rpc-url "${!rpc}" "${signer[@]}" "${params[@]}"

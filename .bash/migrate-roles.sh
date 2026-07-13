#!/bin/bash
# Runs RoleMigration.s.sol on every chain that has a LayerZeroReceiver, EnsoCCIPReceiver,
# or flashloan adapter deployment recorded under broadcast/. Only the most recent
# deployment per chain (run-latest.json) is targeted — older superseded deployments
# are ignored.
#
# Dry-run (simulation only) by default. Pass "broadcast" to send transactions.
#
# New owners are hardcoded per chain in RoleMigration.s.sol (_newOwnerFor).
#
# Required env (.env is sourced): PRIVATE_KEY (deployer key) and the per-chain
# *_RPC_URL vars. Chains with an unset RPC var are skipped.
#
# e.g. migrate-roles.sh            # simulate everywhere
#      migrate-roles.sh broadcast  # execute everywhere

set -uo pipefail
cd "$(dirname "$0")/.."

source .env

: "${PRIVATE_KEY:?PRIVATE_KEY must be set (deployer key)}"

broadcast=${1:-}

# --tempo.fee-token is only available in newer foundry builds (matches deploy.sh usage)
tempo_supported=""
if forge script --help 2>/dev/null | grep -q 'tempo.fee-token'; then
  tempo_supported="yes"
fi

declare -A NETWORK=(
  [1]=ETHEREUM
  [10]=OPTIMISM
  [56]=BSC
  [100]=GNOSIS
  [130]=UNICHAIN
  [137]=POLYGON
  [143]=MONAD
  [146]=SONIC
  [324]=ZKSYNC
  [480]=WORLD
  [999]=HYPER
  [1329]=SEI
  [1868]=SONEIUM
  [4217]=TEMPO
  [4326]=MEGAETH
  [8453]=BASE
  [9745]=PLASMA
  [42161]=ARBITRUM
  [42793]=ETHERLINK
  [43114]=AVALANCHE
  [57073]=INK
  [59144]=LINEA
  [80094]=BERACHAIN
  [98866]=PLUME
  [747474]=KATANA
)

# Union of chains across all relevant deployer broadcasts
chains=$(ls broadcast/LayerZeroDeployer.s.sol broadcast/EnsoCCIPReceiverDeployer.s.sol broadcast/FlashloanAdapterDeployer.s.sol 2>/dev/null \
  | grep -E '^[0-9]+$' | sort -nu)

failed=()
for chain in $chains; do
  network="${NETWORK[$chain]:-}"
  if [[ -z "$network" ]]; then
    echo "!! chain $chain: no network mapping, skipping"
    continue
  fi
  rpc="${network}_RPC_URL"
  url="${!rpc:-}"
  if [[ -z "$url" ]]; then
    echo "!! chain $chain: $rpc not set, skipping"
    continue
  fi

  params=()
  if [[ $network == "ZKSYNC" ]]; then
    params+=(--zksync --slow)
  fi
  if [[ $network == "POLYGON" ]]; then
    params+=(--gas-estimate-multiplier 300)
  fi
  if [[ $network == "TEMPO" ]]; then
    if [[ -z "$tempo_supported" ]]; then
      echo "!! chain $chain: forge $(forge --version | head -1) lacks --tempo.fee-token, skipping (update foundry to migrate Tempo)"
      continue
    fi
    params+=(--tempo.fee-token "0x20c000000000000000000000b9537d11c60e8b50")
  fi
  if [[ $broadcast == "broadcast" ]]; then
    params+=(--broadcast)
  fi

  echo ""
  echo "===== chain $chain ($network) ====="
  if ! PRIVATE_KEY="$PRIVATE_KEY" \
      forge script script/RoleMigration.s.sol --rpc-url "$url" "${params[@]}" -vvv; then
    echo "!! chain $chain FAILED"
    failed+=("$chain")
  fi
done

echo ""
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failed chains: ${failed[*]}"
  exit 1
fi
echo "All chains processed."

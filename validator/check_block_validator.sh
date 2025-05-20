#!/bin/bash

# Path JSON
get_block_height() {
  curl -s "http://localhost:$1/status" | jq -r '.result.sync_info.latest_block_height // empty'
}

# Step 1: Try 26657
OG_RPC_PORT=26657
local_height=$(get_block_height $OG_RPC_PORT)

# Step 2: Fallback to ${OG_PORT}657
if [ -z "$local_height" ] || [ "$local_height" = "null" ]; then
  echo "⚠️  Port 26657 not responding."

  if [ -n "$OG_PORT" ]; then
    fallback_port="${OG_PORT}657"
    echo "⏪ Trying fallback port: $fallback_port"
    OG_RPC_PORT=$fallback_port
    local_height=$(get_block_height $OG_RPC_PORT)
  fi
fi

# Step 3: If it still fails, ask for manual input
if [ -z "$local_height" ] || [ "$local_height" = "null" ]; then
  read -p "❓ Unable to detect port. Please enter the RPC port manually: " manual_port
  OG_RPC_PORT=$manual_port
  local_height=$(get_block_height $OG_RPC_PORT)

  if [ -z "$local_height" ] || [ "$local_height" = "null" ]; then
    echo "❌ Still cannot connect to port $OG_RPC_PORT. Exiting..."
    return 1
  fi
fi

# Monitoring loop
prev_local_height=$local_height
prev_time=$(date +%s)
first_run=true

while true; do
  status_json=$(curl -s "http://localhost:$OG_RPC_PORT/status")
  local_height=$(echo "$status_json" | jq -r '.result.sync_info.latest_block_height // empty')
  catching_up=$(echo "$status_json" | jq -r '.result.sync_info.catching_up // empty')
  peers_count=$(curl -s "http://localhost:$OG_RPC_PORT/net_info" | jq '.result.peers | length')

  response=$(curl -s -X POST https://evmrpc-testnet.0g.ai \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
  hex_height=$(echo "$response" | jq -r '.result')
  network_height=$((hex_height))
  blocks_left=$((network_height - local_height))

  current_time=$(date +%s)

  if [ "$first_run" = true ]; then
    speed="--"
    eta_display=""
    first_run=false
  else
    time_diff=$((current_time - prev_time))
    height_diff=$((local_height - prev_local_height))

    if [ $time_diff -gt 0 ]; then
      speed=$(echo "scale=2; $height_diff / $time_diff" | bc)
    else
      speed=0
    fi

    if [ "$catching_up" = "true" ] && (( $(echo "$speed > 0" | bc -l) )); then
      eta_seconds=$(echo "$blocks_left / $speed" | bc)
      eta_formatted=$(printf '%02dh:%02dm:%02ds' $((eta_seconds/3600)) $((eta_seconds%3600/60)) $((eta_seconds%60)))
      eta_display="| \033[1;33mETA:\033[0m $eta_formatted"
    else
      eta_display=""
    fi
  fi

  echo -e "\033[1;38mYour node height:\033[0m \033[1;34m$local_height\033[0m | \033[1;35mNetwork height:\033[0m \033[1;36m$network_height\033[0m | \033[1;32mPeers:\033[0m $peers_count | \033[1;29mBlocks left:\033[0m \033[1;31m$blocks_left\033[0m | \033[1;32mSpeed:\033[0m ${speed} blk/s $eta_display"

  prev_local_height=$local_height
  prev_time=$current_time

  sleep 5
done

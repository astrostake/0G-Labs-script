#!/bin/bash

# Fungsi untuk prompt port jika gagal
prompt_port() {
  read -p "❗ Cannot connect to 0gchaind. Please enter the correct RPC port (default is 26657): " custom_port
  export OG_RPC_PORT="$custom_port"
}

# Cek awal koneksi dan port
OG_RPC_PORT=26657
status_json=$(curl -s "http://localhost:$OG_RPC_PORT/status")

if ! echo "$status_json" | jq -e . >/dev/null 2>&1; then
  prompt_port
  status_json=$(curl -s "http://localhost:$OG_RPC_PORT/status")
  if ! echo "$status_json" | jq -e . >/dev/null 2>&1; then
    echo "❌ Still failed to connect. Exiting..."
    exit 1
  fi
fi

# Loop utama
prev_local_height=0
prev_time=$(date +%s)
first_run=true

while true; do
  status_json=$(curl -s "http://localhost:$OG_RPC_PORT/status")
  local_height=$(echo "$status_json" | jq -r .result.sync_info.latest_block_height)
  catching_up=$(echo "$status_json" | jq -r .result.sync_info.catching_up)
  peers_count=$(echo "$status_json" | jq -r .result.peers | jq length)

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

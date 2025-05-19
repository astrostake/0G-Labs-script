#!/bin/bash

echo ""
echo "🛰️  AstroStake Block Scanner | Support by Maouam's Node Lab Team"
echo "================================================================"
echo ""

# Detect RPC from Systemd Service
SYSTEMD_SERVICE="/etc/systemd/system/zgs.service"
if [[ -f "$SYSTEMD_SERVICE" ]]; then
    RPC_URL=$(grep -oP '(?<=--rpc\s)[^ ]+|(?<=--blockchain_rpc_endpoint\s)[^ ]+' "$SYSTEMD_SERVICE" | head -n 1)
fi

# If RPC from systemd is not found, check from config.toml
if [[ -z "$RPC_URL" ]]; then
    RPC_URL=$(grep 'blockchain_rpc_endpoint' $HOME/0g-storage-node/run/config.toml | cut -d '"' -f2)
fi

# If there is still no RPC URL, use the default and issue a warning.
if [[ -z "$RPC_URL" ]]; then
    RPC_URL="https://0g-testnet-rpc.astrostake.xyz"
    echo -e "❌ RPC URL is not detected in systemd service or config.toml."
    echo -e "🌐 Using default RPC for network block checking: \033[1;34m$RPC_URL\033[0m"
fi

# Display RPC used
echo -e "🔗 RPC: \033[1;34m$RPC_URL\033[0m"
echo -e ""

# Cek versi node
cd $HOME/0g-storage-node
VERSION=$(git describe --tags --abbrev=0 2>/dev/null)
if [[ -n "$VERSION" ]]; then
    echo -e "🧩 Storage Node Version: \e[1;32m$VERSION\e[0m"
else
    echo -e "🧩 Storage Node Version: \e[31mUnknown\e[0m"
fi

echo -e ""

prev_block=0
prev_time=0

while true; do 
    # Fetch local node status
    LOCAL_RESPONSE=$(curl -s -X POST http://127.0.0.1:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
    logSyncHeight=$(echo "$LOCAL_RESPONSE" | jq '.result.logSyncHeight' 2>/dev/null)
    connectedPeers=$(echo "$LOCAL_RESPONSE" | jq '.result.connectedPeers' 2>/dev/null)

    # Fetch network block number
    NETWORK_RESPONSE=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    latestBlockHex=$(echo "$NETWORK_RESPONSE" | jq -r '.result' 2>/dev/null)

    # Validasi status block
    if [[ "$logSyncHeight" =~ ^[0-9]+$ ]]; then
        local_status="$logSyncHeight"
    else
        local_status="N/A"
    fi

    [[ "$connectedPeers" =~ ^[0-9]+$ ]] || connectedPeers=0  # Default to 0 if error

    if [[ "$NETWORK_RESPONSE" == *"rate limit"* || "$NETWORK_RESPONSE" == *"Too Many Requests"* ]]; then
        network_status="N/A (RPC Rate Limited)"
    elif [[ -z "$NETWORK_RESPONSE" || "$NETWORK_RESPONSE" == "null" ]]; then
        network_status="N/A (RPC Timeout)"
    elif [[ "$latestBlockHex" =~ ^0x[0-9a-fA-F]+$ ]]; then
        latestBlock=$((16#${latestBlockHex:2}))
        network_status="$latestBlock"
    else
        network_status="N/A (Invalid RPC Response)"
    fi

    # Hitung BPS dan ETA
    extra_info=""
    if [[ "$logSyncHeight" =~ ^[0-9]+$ && "$latestBlock" =~ ^[0-9]+$ ]]; then
        block_diff=$((latestBlock - logSyncHeight))
        current_time=$(date +%s)

        if [[ "$prev_block" =~ ^[0-9]+$ && "$prev_time" =~ ^[0-9]+$ ]]; then
            delta_block=$((logSyncHeight - prev_block))
            delta_time=$((current_time - prev_time))

            if (( delta_time > 0 && delta_block >= 0 )); then
                bps=$(echo "scale=2; $delta_block / $delta_time" | bc)
                if (( block_diff > 0 && $(echo "$bps > 0" | bc -l) )); then
                    eta_sec=$(echo "scale=0; $block_diff / $bps" | bc)
                    if (( eta_sec < 60 )); then
                        eta_display="$eta_sec sec"
                    elif (( eta_sec < 3600 )); then
                        eta_display="$((eta_sec / 60)) min"
                    elif (( eta_sec < 86400 )); then
                        eta_display="$((eta_sec / 3600)) hr"
                    else
                        eta_display="$((eta_sec / 86400)) day(s)"
                    fi
                    extra_info="| Speed: ${bps} blocks/s | ETA: ${eta_display}"
                else
                    extra_info="| Speed: 0 blocks/s | ETA: ∞"
                fi
            fi
        fi

        prev_block=$logSyncHeight
        prev_time=$current_time

        # Set warna berdasarkan selisih block
        if [ "$block_diff" -le 5 ]; then
            diff_color="\\033[32m" # Hijau
        elif [ "$block_diff" -le 20 ]; then
            diff_color="\\033[33m" # Kuning
        else
            diff_color="\\033[31m" # Merah
        fi

        block_status="(\033[0m${diff_color}Behind $block_diff\033[0m)"
    else
        block_status=""
    fi

    # Tampilkan status
    echo -e "Local Block: \033[32m$local_status\033[0m / Network Block: \033[33m$network_status\033[0m $block_status | Peers: \033[34m$connectedPeers\033[0m $extra_info"
    sleep 5
done

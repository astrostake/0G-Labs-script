#!/bin/bash

bold() { echo -e "\033[1m$1\033[0m"; }

echo ""
bold "🚀 AstroStake Snapshot Installer"
echo "=========================================="
bold "1) 📥 Install Full Snapshot (db)"
bold "2) 📥 Install Light Snapshot (flow_db only)"
echo "=========================================="
read -p "$(bold '👉 Please choose an option (1 or 2): ')" OPTION
echo ""

SNAPSHOT_FILE=""
SNAPSHOT_URL=""
EXTRACT_PATH="$HOME/0g-storage-node/run"

if [[ "$OPTION" == "1" ]]; then
    SNAPSHOT_FILE="snapshot_storage_node_astrostake.tar.lz4"
    SNAPSHOT_URL="https://vault.astrostake.xyz/0g-labs/snapshot_storage_node_astrostake.tar.lz4"
    bold "📦 You selected: Full Snapshot (db)"
elif [[ "$OPTION" == "2" ]]; then
    SNAPSHOT_FILE="snapshot_storage_node_flow_db_astrostake.tar.lz4"
    SNAPSHOT_URL="https://vault.astrostake.xyz/0g-labs/snapshot_storage_node_flow_db_astrostake.tar.lz4"
    EXTRACT_PATH="$HOME/0g-storage-node/run/db"
    bold "📦 You selected: Light Snapshot (flow_db only)"
else
    bold "❌ Invalid option. Exiting..."
    exit 1
fi

echo ""
bold "🔧 Installing dependencies (wget, lz4, pv)..."
sudo apt-get update -qq > /dev/null
sudo apt-get install -y -qq wget lz4 pv > /dev/null
bold "✅ Dependencies installed."
echo ""

if [ -f "$SNAPSHOT_FILE" ]; then
    bold "✅ Snapshot file already exists: $SNAPSHOT_FILE"
else
    bold "📥 Downloading snapshot from:"
    echo "$SNAPSHOT_URL"
    wget --progress=bar:force "$SNAPSHOT_URL" -O "$SNAPSHOT_FILE"
fi
echo ""

bold "🛑 Stopping zgs.service..."
sudo systemctl stop zgs.service
echo ""

if [[ "$OPTION" == "1" ]]; then
    bold "🗑️  Removing entire db folder..."
    rm -rf "$HOME/0g-storage-node/run/db"
elif [[ "$OPTION" == "2" ]]; then
    bold "🧹 Removing old flow_db and data_db folders..."
    rm -rf "$HOME/0g-storage-node/run/db/flow_db"
    rm -rf "$HOME/0g-storage-node/run/db/data_db"
fi

bold "📦 Extracting snapshot..."
mkdir -p "$EXTRACT_PATH"
pv -pterb "$SNAPSHOT_FILE" | lz4 -c -d | tar -x -C "$EXTRACT_PATH"
bold "✅ Snapshot extracted to: $EXTRACT_PATH"
echo ""

bold "🚀 Restarting zgs.service..."
sudo systemctl daemon-reload
sudo systemctl enable zgs > /dev/null
sudo systemctl start zgs
sudo systemctl status zgs --no-pager
echo ""

bold "🎉 Snapshot installation complete and node is running."
read -p "$(bold '🗑️  Delete the snapshot file to save space? (y/n): ')" DELETE_SNAPSHOT
if [[ "$DELETE_SNAPSHOT" =~ ^[Yy]$ ]]; then
    rm -f "$SNAPSHOT_FILE"
    bold "🗑️  Snapshot file deleted."
else
    bold "📦 Snapshot file kept."
fi


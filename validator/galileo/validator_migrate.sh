#!/bin/bash

# =================================================================================================
# 0G Galileo Node Migration Script
#
# Description:
# This script is designed for users who previously installed the node using an older
# auto-installer script. Its purpose is to migrate the setup to a better structure and
# configuration that aligns with the latest manual guide, without losing data or validator identity.
#
# Usage:
# 1. Save this script as `validator_migrate.sh`.
# 2. Grant execution permissions: `chmod +x validator_migrate.sh`
# 3. Run the script: `./validator_migrate.sh`
# =================================================================================================

# --- Initial Configuration and Functions ---
set -e

# Function for better logging
log_info() {
    echo ""
    echo "------------------------------------------------"
    echo "➡️  $1"
    echo "------------------------------------------------"
}

# --- Start Migration Process ---

log_info "Starting the 0G Node Migration Process"
echo "This script will stop your node, back up critical keys,"
echo "restructure directories and configurations, and then restart the node."
echo ""
read -p "Are you ready to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Migration cancelled."
    exit 1
fi

# Get user input for the new configuration
read -p "Please re-enter your MONIKER (the one you want to use): " MONIKER
read -p "Please enter your desired PORT PREFIX (e.g., 55): " OG_PORT

# 1. Back Up Critical Keys
log_info "Step 1: Backing Up Validator Keys..."
sudo systemctl stop 0gchaind geth 2>/dev/null || true

OLD_CONFIG_DIR="$HOME/.0gchaind/0g-home/0gchaind-home/config"
BACKUP_DIR="$HOME/0g_migration_backup_$(date +%F-%H%M%S)"

if [ -d "$OLD_CONFIG_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$OLD_CONFIG_DIR/priv_validator_key.json" "$BACKUP_DIR/"
    cp "$OLD_CONFIG_DIR/node_key.json" "$BACKUP_DIR/"
    cp "$HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json" "$BACKUP_DIR/"
    echo "✅ Backup successful. Keys are saved in: $BACKUP_DIR"
else
    echo "❌ Error: Old configuration directory not found. Are you sure the old installation exists?"
    exit 1
fi

# 2. Restructure Directories to Match Manual Guide
log_info "Step 2: Restructuring directories..."

# New path according to the manual guide
NEW_OG_HOME_DIR="$HOME/.0gchaind/galileo"
# Create the new base directory
mkdir -p "$NEW_OG_HOME_DIR"

# Download a clean version of the repo to get the correct file structure
cd $HOME
wget https://github.com/0glabs/0gchain-NG/releases/download/v1.2.0/galileo-v1.2.0.tar.gz -O temp_galileo.tar.gz
tar -xzvf temp_galileo.tar.gz -C "$NEW_OG_HOME_DIR" --strip-components=1
rm temp_galileo.tar.gz

# Move old data to the new structure to avoid re-syncing
echo "Moving old blockchain data..."
mv "$HOME/.0gchaind/0g-home/geth-home" "$NEW_OG_HOME_DIR/0g-home/"
mv "$HOME/.0gchaind/0g-home/0gchaind-home/data" "$NEW_OG_HOME_DIR/0g-home/0gchaind-home/"
# Remove the rest of the old 0g-home directory
rm -rf "$HOME/.0gchaind/0g-home"

# Restore the critical keys to their new location
echo "Restoring validator keys to their new location..."
cp "$BACKUP_DIR/priv_validator_key.json" "$NEW_OG_HOME_DIR/0g-home/0gchaind-home/config/"
cp "$BACKUP_DIR/node_key.json" "$NEW_OG_HOME_DIR/0g-home/0gchaind-home/config/"
cp "$BACKUP_DIR/priv_validator_state.json" "$NEW_OG_HOME_DIR/0g-home/0gchaind-home/data/"

echo "✅ Directory structure successfully migrated."

# 3. Apply New Configuration
log_info "Step 3: Applying new configuration..."

NEW_CONFIG_DIR="$NEW_OG_HOME_DIR/0g-home/0gchaind-home/config"
NEW_GETH_CONFIG="$NEW_OG_HOME_DIR/geth-config.toml"

# Run all 'sed' commands from the manual guide
sed -i -e "s/^moniker *=.*/moniker = \"$MONIKER\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/HTTPPort = .*/HTTPPort = ${OG_PORT}545/" "$NEW_GETH_CONFIG"
sed -i "s/WSPort = .*/WSPort = ${OG_PORT}546/" "$NEW_GETH_CONFIG"
sed -i "s/AuthPort = .*/AuthPort = ${OG_PORT}551/" "$NEW_GETH_CONFIG"
sed -i "s/ListenAddr = .*/ListenAddr = \":${OG_PORT}303\"/" "$NEW_GETH_CONFIG"
sed -i "s/laddr = \"tcp:\/\/0\.0\.0\.0:26656\"/laddr = \"tcp:\/\/0\.0\.0\.0:${OG_PORT}656\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/laddr = \"tcp:\/\/127\.0\.0\.1:26657\"/laddr = \"tcp:\/\/127\.0\.0\.1:${OG_PORT}657\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/^proxy_app = .*/proxy_app = \"tcp:\/\/127\.0\.0\.1:${OG_PORT}658\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/^pprof_laddr = .*/pprof_laddr = \"0.0.0.0:${OG_PORT}060\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/prometheus_listen_addr = \".*\"/prometheus_listen_addr = \"0.0.0.0:${OG_PORT}660\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i "s/address = \".*:3500\"/address = \"127.0.0.1:${OG_PORT}500\"/" "$NEW_CONFIG_DIR/app.toml"
sed -i "s/^rpc-dial-url *=.*/rpc-dial-url = \"http:\/\/localhost:${OG_PORT}551\"/" "$NEW_CONFIG_DIR/app.toml"
sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" "$NEW_CONFIG_DIR/app.toml"
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" "$NEW_CONFIG_DIR/app.toml"
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"19\"/" "$NEW_CONFIG_DIR/app.toml"
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" "$NEW_CONFIG_DIR/config.toml"
sed -i 's/HTTPHost = .*/HTTPHost = "127.0.0.1"/' "$NEW_GETH_CONFIG"
sed -i "s|laddr = \"tcp://0.0.0.0:${OG_PORT}657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" "$NEW_CONFIG_DIR/config.toml"

echo "✅ Configuration files successfully updated."

# 4. Recreate Systemd Service Files
log_info "Step 4: Recreating systemd service files..."

# Remove old services if they exist
sudo rm -f /etc/systemd/system/0gchaind.service
sudo rm -f /etc/systemd/system/geth.service

# Create new 0gchaind service file
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=devnet
WorkingDirectory=$NEW_OG_HOME_DIR
ExecStart=/usr/local/bin/0gchaind start \
  --chaincfg.chain-spec devnet \
  --home $NEW_OG_HOME_DIR/0g-home/0gchaind-home \
  --chaincfg.kzg.trusted-setup-path=$NEW_OG_HOME_DIR/kzg-trusted-setup.json \
  --chaincfg.engine.jwt-secret-path=$NEW_OG_HOME_DIR/jwt-secret.hex \
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \
  --p2p.seeds=85a9b9a1b7fa0969704db2bc37f7c100855a75d9@8.218.88.60:26656
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Create new geth service file
sudo tee /etc/systemd/system/geth.service > /dev/null <<EOF
[Unit]
Description=0g Geth Node Service
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$NEW_OG_HOME_DIR
ExecStart=/usr/local/bin/geth \
  --config $NEW_OG_HOME_DIR/geth-config.toml \
  --datadir $NEW_OG_HOME_DIR/0g-home/geth-home \
  --http.port ${OG_PORT}545 \
  --ws.port ${OG_PORT}546 \
  --authrpc.port ${OG_PORT}551 \
  --bootnodes enode://de7b86d8ac452b1413983049c20eafa2ea0851a3219c2cc12649b971c1677bd83fe24c5331e078471e52a94d95e8cde84cb9d866574fec957124e57ac6056699@8.218.88.60:30303 \
  --port ${OG_PORT}303 \
  --networkid 16601
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Systemd service files successfully recreated."


# 6. Finalize and Restart
log_info "Step 5: Finalizing and restarting all services..."
sudo systemctl daemon-reload
sudo systemctl enable 0gchaind
sudo systemctl enable geth
sudo systemctl start 0gchaind
sudo systemctl start geth

# --- Done ---
log_info "✅ Migration Complete!"
echo ""
echo "==================================================================================="
echo "  Congratulations! Your node has been successfully migrated to the new setup."
echo "  Your directory structure and configuration now match the latest manual guide."
echo ""
echo "  To check the logs, use the command:"
echo "  ➡️   journalctl -u 0gchaind -u geth -f"
echo "==================================================================================="

#!/bin/bash

set -e

read -p "Enter your MONIKER value: " MONIKER
SERVER_IP=$(hostname -I | awk '{print $1}')

# Cleanup
echo "🧹 Cleaning old setup..."
sudo systemctl stop 0gchaind 2>/dev/null || true
sudo systemctl stop geth 2>/dev/null || true
sudo systemctl disable 0gchaind 2>/dev/null || true
sudo systemctl disable geth 2>/dev/null || true

rm -rf $HOME/galileo
rm -rf $HOME/.0gchaind
rm -f $HOME/go/bin/0gchaind
sed -i '/galileo\/bin/d' $HOME/.bash_profile || true

# Download & extract
echo "⬇️ Downloading Galileo..."
cd $HOME
wget https://github.com/0glabs/0gchain-NG/releases/download/v1.1.1/galileo-v1.1.1.tar.gz
tar -xzf galileo-v1.1.1.tar.gz
rm galileo-v1.1.1.tar.gz
cd galileo

sudo mv ./bin/geth /usr/local/bin/geth
sudo mv ./bin/0gchaind /usr/local/bin/0gchaind
sudo chmod +x /usr/local/bin/geth /usr/local/bin/0gchaind

# Init Geth
echo "⚙️ Initializing Geth..."
/usr/local/bin/geth init --datadir $HOME/galileo/0g-home/geth-home ./genesis.json

# Init 0gchaind
echo "⚙️ Initializing 0gchaind..."
/usr/local/bin/0gchaind init "$MONIKER" --home $HOME/galileo/tmp

# Copy node files to 0gchaind home directory
cp $HOME/galileo/tmp/data/priv_validator_state.json $HOME/galileo/0g-home/0gchaind-home/data/
cp $HOME/galileo/tmp/config/node_key.json $HOME/galileo/0g-home/0gchaind-home/config/
cp $HOME/galileo/tmp/config/priv_validator_key.json $HOME/galileo/0g-home/0gchaind-home/config/

# Prepare best practice layout
echo "📁 Moving 0g-home to ~/.0gchaind..."
mkdir -p $HOME/.0gchaind
mv $HOME/galileo/0g-home $HOME/.0gchaind/

# Trusted setup / jwt files
echo "🔐 Ensuring trusted setup files exist..."
[ ! -f "$HOME/galileo/jwt-secret.hex" ] && openssl rand -hex 32 > $HOME/galileo/jwt-secret.hex
[ ! -f "$HOME/galileo/kzg-trusted-setup.json" ] && curl -L -o $HOME/galileo/kzg-trusted-setup.json https://danksharding.io/trusted-setup/kzg-trusted-setup.json

# Systemd service for 0gchaind
echo "📝 Writing systemd service: 0gchaind..."

sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
[Unit]
Description=0GChainD Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/galileo
ExecStart=/usr/local/bin/0gchaind start \
    --rpc.laddr tcp://0.0.0.0:26657 \
    --chain-spec devnet \
    --kzg.trusted-setup-path=$HOME/galileo/kzg-trusted-setup.json \
    --engine.jwt-secret-path=$HOME/galileo/jwt-secret.hex \
    --kzg.implementation=crate-crypto/go-kzg-4844 \
    --block-store-service.enabled \
    --node-api.enabled \
    --node-api.logging \
    --node-api.address 0.0.0.0:3500 \
    --pruning=nothing \
    --home=$HOME/.0gchaind/0g-home/0gchaind-home \
    --p2p.seeds=85a9b9a1b7fa0969704db2bc37f7c100855a75d9@8.218.88.60:26656 \
    --p2p.external_address=$SERVER_IP:26656
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Systemd service for geth
echo "📝 Writing systemd service: geth..."
sudo tee /etc/systemd/system/geth.service > /dev/null <<EOF
[Unit]
Description=Geth Service for 0GChainD
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/galileo
ExecStart=/usr/local/bin/geth --config $HOME/galileo/geth-config.toml \
    --nat extip:$SERVER_IP \
    --bootnodes enode://de7b86d8ac452b1413983049c20eafa2ea0851a3219c2cc12649b971c1677bd83fe24c5331e078471e52a94d95e8cde84cb9d866574fec957124e57ac6056699@8.218.88.60:30303 \
    --datadir $HOME/.0gchaind/0g-home/geth-home \
    --networkid 16601
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Start everything
echo "🔁 Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable geth
sudo systemctl enable 0gchaind
sudo systemctl start geth
sudo systemctl start 0gchaind

echo "✅ All done. Geth and 0gchaind are running!"
journalctl -u 0gchaind -u geth -f

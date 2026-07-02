#!/bin/bash
# Codex Relay Station - One-click Deployment Script
# Deploys ChatGPT Plus -> API relay station on Ubuntu 22.04+
#
# Usage:
#   chmod +x deploy.sh && sudo ./deploy.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[-]${NC} $1"; exit 1; }

# Check root
[ "$EUID" -ne 0 ] && err "Please run as root: sudo ./deploy.sh"

echo "============================================"
echo "  Codex Relay Station Deployment"
echo "============================================"
echo ""

# ---- Step 1: System Update ----
log "Updating system packages..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release sqlite3

# ---- Step 2: Install Docker ----
if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
else
    log "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    log "Docker installed: $(docker --version)"
fi

# ---- Step 3: Configure Docker ----
log "Configuring Docker daemon..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": { "nofile": { "Name": "nofile", "Hard": 65535, "Soft": 65535 } }
}
EOF
systemctl restart docker

# ---- Step 4: Security Hardening ----
log "Setting up security..."

# Install fail2ban
apt-get install -y fail2ban
NEW_SSH_PORT=28953

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true
port = 22,${NEW_SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Configure UFW
apt-get install -y ufw
ufw allow ${NEW_SSH_PORT}/tcp
ufw allow 3000/tcp   # New API
ufw allow 5005/tcp   # chat2api
ufw --force enable

# Change SSH port
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
if ! grep -q "Port ${NEW_SSH_PORT}" /etc/ssh/sshd_config; then
    sed -i "s/^#Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config
    if ! grep -q "Port ${NEW_SSH_PORT}" /etc/ssh/sshd_config; then
        echo "Port ${NEW_SSH_PORT}" >> /etc/ssh/sshd_config
    fi
    sshd -t && systemctl restart sshd
    ufw delete allow 22/tcp 2>/dev/null || true
fi

log "SSH port changed to ${NEW_SSH_PORT}"
log "Firewall configured"

# ---- Step 5: Deploy Services ----
log "Deploying relay station services..."

mkdir -p /opt/relay-station/data/new-api

cat > /opt/relay-station/docker-compose.yml << 'EOF'
services:
  new-api:
    image: calciumion/new-api:latest
    container_name: new-api
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - /opt/relay-station/data/new-api:/data
    environment:
      - TZ=Asia/Tokyo
      - SYNC_FREQUENCY=120
      - BATCH_UPDATE_ENABLED=true
      - MEMORY_CACHE_ENABLED=true
    mem_limit: 300m
    memswap_limit: 500m
    depends_on:
      - chat2api

  chat2api:
    image: lanqian528/chat2api:latest
    container_name: chat2api
    restart: always
    ports:
      - "5005:5005"
    environment:
      - TZ=Asia/Tokyo
    mem_limit: 200m
    memswap_limit: 300m
EOF

cd /opt/relay-station
docker compose pull
docker compose up -d

log "Waiting for services to start..."
sleep 10

# ---- Step 6: Verify ----
log "Verifying deployment..."
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check HTTP
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/)
if [ "$HTTP_CODE" = "200" ]; then
    log "New API is running (HTTP 200)"
else
    warn "New API returned HTTP $HTTP_CODE"
fi

CHAT_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5005/ 2>/dev/null || echo "000")
log "chat2api status: HTTP $CHAT_CODE"

# ---- Step 7: Print Summary ----
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "  Management Panel: http://${SERVER_IP}:3000"
echo "  Default Login:    root / 123456"
echo "  SSH Port:         ${NEW_SSH_PORT}"
echo ""
echo "  IMPORTANT NEXT STEPS:"
echo "  1. Login and change the default password"
echo "  2. Get your ChatGPT access token from:"
echo "     https://chatgpt.com/api/auth/session"
echo "  3. Add a channel in the admin panel:"
echo "     - Type: OpenAI"
echo "     - Base URL: http://172.17.0.1:5005"
echo "     - Key: your ChatGPT access token"
echo "     - Models: gpt-4o,gpt-4o-mini,o3-mini,gpt-5.5"
echo "  4. Create user accounts and generate API keys"
echo ""
echo "  For friends to use:"
echo "    API Base: http://${SERVER_IP}:3000/v1"
echo "    API Key:  (their assigned sk-xxx key)"
echo ""
echo "============================================"

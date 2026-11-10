#!/bin/bash
# Quick deploy script for testing on trial VPS
# Usage: bash deploy-test.sh
# Installs Xray (XHTTP + gRPC + REALITY) and Hysteria2, outputs connection links

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run as root"

# --- Gather info ---
SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me || curl -s4 --max-time 5 api.ipify.org)
[[ -z "$SERVER_IP" ]] && err "Could not detect server IP"

UUID=$(cat /proc/sys/kernel/random/uuid)
HY2_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
SNI="www.microsoft.com"

echo -e "\n${CYAN}=== Xray + Hysteria2 Deploy ===${NC}"
log "Server IP:  $SERVER_IP"
log "UUID:       $UUID"
log "Short ID:   $SHORT_ID"

# --- Dependencies ---
log "Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip curl openssl

# --- Install Xray ---
log "Installing Xray..."
curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o /tmp/install-xray.sh
bash /tmp/install-xray.sh install 2>&1 | tail -3
export PATH=$PATH:/usr/local/bin

# --- Generate REALITY keys ---
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
log "REALITY keys generated"

# --- Install Hysteria2 ---
log "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3

# --- Generate self-signed cert for Hysteria2 ---
mkdir -p /etc/hysteria
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -days 36500 -subj "/CN=bing.com" 2>/dev/null

CERT_SHA256=$(openssl x509 -in /etc/hysteria/server.crt -noout -fingerprint -sha256 \
  | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')

# --- Xray config ---
mkdir -p /usr/local/etc/xray /var/log/xray

cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "tag": "xhttp",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "email": "user" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "dest": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "fingerprint": "chrome"
        },
        "xhttpSettings": {
          "path": "/download",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "grpc",
      "port": 2053,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "email": "user" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "dest": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "fingerprint": "chrome"
        },
        "grpcSettings": {
          "serviceName": "grpc"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

# --- Hysteria2 config ---
cat > /etc/hysteria/config.yaml << EOF
listen: :8443

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: "$HY2_PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

# --- Firewall ---
if command -v ufw &>/dev/null; then
  ufw allow 443/tcp comment 'Xray XHTTP' >/dev/null
  ufw allow 2053/tcp comment 'Xray gRPC' >/dev/null
  ufw allow 8443/udp comment 'Hysteria2' >/dev/null
  log "Firewall rules added"
fi

# --- Start services ---
systemctl enable xray hysteria-server 2>/dev/null || true
systemctl restart xray
systemctl restart hysteria-server
sleep 2

# --- Verify ---
xray_ok=false
hy2_ok=false
systemctl is-active xray --quiet && xray_ok=true
systemctl is-active hysteria-server --quiet && hy2_ok=true

$xray_ok && log "Xray running" || warn "Xray failed to start"
$hy2_ok && log "Hysteria2 running" || warn "Hysteria2 failed to start"

# --- Output links ---
XHTTP_LINK="vless://$UUID@$SERVER_IP:443?encryption=none&type=xhttp&security=reality&path=%2Fdownload&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID#xhttp"
GRPC_LINK="vless://$UUID@$SERVER_IP:2053?encryption=none&type=grpc&security=reality&serviceName=grpc&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID#grpc"
HY2_LINK="hysteria2://$HY2_PASSWORD@$SERVER_IP:8443?pinSHA256=$CERT_SHA256&sni=bing.com#hysteria2"

echo -e "\n${CYAN}=== Connection Links ===${NC}\n"

echo -e "${YELLOW}XHTTP + REALITY (port 443):${NC}"
echo "$XHTTP_LINK"

echo -e "\n${YELLOW}gRPC + REALITY (port 2053):${NC}"
echo "$GRPC_LINK"

echo -e "\n${YELLOW}Hysteria2 (port 8443/UDP):${NC}"
echo "$HY2_LINK"

echo -e "\n${CYAN}=== Done ===${NC}"

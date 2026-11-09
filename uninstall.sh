#!/bin/bash
# Uninstall Xray and Hysteria2
# Usage: bash uninstall.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run as root"

# Stop and disable services
log "Stopping services..."
systemctl stop xray 2>/dev/null || true
systemctl stop hysteria-server 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
systemctl disable hysteria-server 2>/dev/null || true

# Uninstall Xray
if [[ -f /usr/local/bin/xray ]]; then
  log "Removing Xray..."
  bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge 2>&1 | tail -2
fi

# Uninstall Hysteria2
if [[ -f /usr/local/bin/hysteria ]]; then
  log "Removing Hysteria2..."
  bash <(curl -fsSL https://get.hy2.sh/) --remove 2>&1 | tail -2
fi

# Remove configs
log "Removing configs..."
rm -rf /etc/hysteria
rm -rf /usr/local/etc/xray
rm -rf /var/log/xray

# Remove firewall rules
if command -v ufw &>/dev/null; then
  ufw delete allow 443/tcp 2>/dev/null || true
  ufw delete allow 2053/tcp 2>/dev/null || true
  ufw delete allow 8443/udp 2>/dev/null || true
  log "Firewall rules removed"
fi

log "Done"

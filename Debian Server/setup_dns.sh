#!/bin/bash
# Purpose: Configures local DNS resolution for lumina.hub on a Debian-based
#          system using dnsmasq. Also adds a static /etc/hosts entry.
# Usage:   sudo ./setup_dns.sh
# Args:    None (uses hardcoded DOMAIN="lumina.hub" and HUB_IP="192.168.1.1")
# Idempotent: Yes — overwrites /etc/dnsmasq.d/lumina.conf on each run and
#             skips /etc/hosts if the entry already exists.
set -e

DOMAIN="lumina.hub"
HUB_IP="192.168.1.1"

echo "[INFO] Setting up local domain: $DOMAIN -> $HUB_IP..."

# 1. Install dnsmasq
sudo apt update
sudo apt install -y dnsmasq

# 2. Dynamically detect Wi-Fi interface
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
if [ -z "$WIFI_IF" ]; then
    WIFI_IF="wlan0" # fallback
fi
echo "[INFO] Detected Wi-Fi interface: $WIFI_IF"

# 3. Configure dnsmasq to resolve our domain
sudo bash -c "cat > /etc/dnsmasq.d/lumina.conf <<EOF
address=/$DOMAIN/$HUB_IP
interface=lo
interface=$WIFI_IF
bind-interfaces
EOF"

# 3. Add to local hosts file for good measure
grep -q "$HUB_IP $DOMAIN" /etc/hosts || sudo bash -c "echo '$HUB_IP $DOMAIN' >> /etc/hosts"

# 4. Restart service
sudo systemctl restart dnsmasq

echo "[SUCCESS] You can now access the Hub at http://$DOMAIN:8000"

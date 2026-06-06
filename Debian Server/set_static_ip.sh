#!/bin/bash
# Purpose: Applies a static IPv4 address to the primary network interface
#          (ethernet or Wi-Fi) using NetworkManager's nmcli.
# Usage:   sudo ./set_static_ip.sh
# Args:    None (uses defaults: STATIC_IP="192.168.1.1/24", GATEWAY="192.168.1.1",
#          DNS="8.8.8.8")
# Idempotent: Yes — overwrites the existing connection profile's IPv4 settings
#             on each run.
set -e

STATIC_IP="192.168.1.1/24"
GATEWAY="192.168.1.1"
DNS="8.8.8.8"

echo "[INFO] Configuring Static IP: $STATIC_IP..."

# Get the name of the primary ethernet or wifi interface
DEFAULT_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet" || $2=="wifi" {print $1; exit}')
if [ -z "$DEFAULT_IF" ]; then
    echo "[ERROR] No network interface found."
    exit 1
fi

INTERFACE=$DEFAULT_IF

echo "Using interface: $INTERFACE"

# Get the active connection profile name for the interface
CON_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$INTERFACE$" | cut -d: -f1)
if [ -z "$CON_NAME" ]; then
    echo "[ERROR] No active connection profile found for $INTERFACE"
    exit 1
fi

# Apply static IP via nmcli (Modern Debian/Ubuntu)
sudo nmcli con modify "$CON_NAME" ipv4.addresses "$STATIC_IP"
sudo nmcli con modify "$CON_NAME" ipv4.gateway "$GATEWAY"
sudo nmcli con modify "$CON_NAME" ipv4.dns "$DNS"
sudo nmcli con modify "$CON_NAME" ipv4.method manual
sudo nmcli con up "$CON_NAME"

echo "[SUCCESS] Static IP applied! The Hub is now at $STATIC_IP"

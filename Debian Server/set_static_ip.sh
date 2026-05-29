#!/bin/bash
set -e
# Lumina Hub - Static IP Configuration

STATIC_IP="192.168.1.1/24"
GATEWAY="192.168.1.1"
DNS="8.8.8.8"

echo "[INFO] Configuring Static IP: $STATIC_IP..."

# Get the name of the primary ethernet or wifi interface
INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5}')

if [ -z "$INTERFACE" ]; then
    INTERFACE=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | head -n1 | cut -d: -f1)
fi

echo "Using interface: $INTERFACE"

# Apply static IP via nmcli (Modern Debian/Ubuntu)
sudo nmcli con modify "$INTERFACE" ipv4.addresses "$STATIC_IP"
sudo nmcli con modify "$INTERFACE" ipv4.gateway "$GATEWAY"
sudo nmcli con modify "$INTERFACE" ipv4.dns "$DNS"
sudo nmcli con modify "$INTERFACE" ipv4.method manual
sudo nmcli con up "$INTERFACE"

echo "[SUCCESS] Static IP applied! The Hub is now at $STATIC_IP"

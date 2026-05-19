#!/bin/bash
# Lumina Hub - Start Offline Hotspot
# This script forcefully takes control of the Wi-Fi card and creates the Hub network.

echo "[INFO] Initializing Wi-Fi Hotspot (Lumina Hub)..."

# 1. Force NetworkManager to manage all interfaces
sudo sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf

# 2. Kill manual wpa_supplicant connections that are locking the device
sudo killall wpa_supplicant 2>/dev/null

# 3. Restart NetworkManager to apply changes
sudo systemctl restart NetworkManager
echo "Waiting for NetworkManager to restart..."
sleep 5

# 4. Detect Wi-Fi interface dynamically
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
if [ -z "$WIFI_IF" ]; then
    echo "[ERROR] Could not detect a Wi-Fi interface."
    exit 1
fi
echo "[INFO] Found Wi-Fi interface: $WIFI_IF"

# 5. Create a bulletproof Hotspot Connection Profile
echo "[INFO] Creating Hotspot Profile..."
sudo nmcli connection delete LuminaHub 2>/dev/null
sudo nmcli connection add type wifi ifname "$WIFI_IF" con-name LuminaHub autoconnect yes ssid "Lumina Hub"
sudo nmcli connection modify LuminaHub 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
sudo nmcli connection modify LuminaHub wifi-sec.key-mgmt wpa-psk wifi-sec.psk "lumina2026"

echo "[INFO] Starting Hotspot (SSH will drop now!)..."
sudo nmcli connection up LuminaHub
echo "[SUCCESS] Hotspot 'Lumina Hub' is now active!"

#!/bin/bash
# Lumina Hub - Start Offline Hotspot
# This script forcefully takes control of the Wi-Fi card and creates the Hub network.

echo "📡 Initializing Wi-Fi Hotspot (Lumina Hub)..."

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
    echo "❌ Error: Could not detect a Wi-Fi interface."
    exit 1
fi
echo "📡 Found Wi-Fi interface: $WIFI_IF"

# 5. Explicitly set to managed and create hotspot
sudo nmcli device set "$WIFI_IF" managed yes
sudo nmcli device wifi hotspot ifname "$WIFI_IF" ssid "Lumina Hub" password "lumina2026"

echo "✅ Hotspot 'Lumina Hub' is now active!"

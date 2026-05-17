#!/bin/bash
# Lumina Hub - Restore Home Wi-Fi & SSH Access
# This script shuts down the Hotspot and reconnects to your known Home Wi-Fi

echo "🔄 Shutting down Lumina Hub Hotspot..."
sudo nmcli connection down LuminaHub 2>/dev/null
sudo nmcli connection down Hotspot 2>/dev/null

echo "📡 Searching for known networks (Home Wi-Fi)..."
# Restart NetworkManager so it automatically connects to the highest priority known network
sudo systemctl restart NetworkManager
sleep 3

echo "✅ The Hub has been taken offline."
echo "Your server should now be reconnected to your home Wi-Fi."
echo "You can SSH back into the server from your laptop!"

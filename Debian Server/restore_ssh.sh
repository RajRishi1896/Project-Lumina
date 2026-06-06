#!/bin/bash
# Purpose: Shuts down the Lumina Hub hotspot and restores the normal Wi-Fi
#          connection so the device can be accessed via SSH on the home
#          network.
# Usage:   sudo ./restore_ssh.sh
# Args:    None
# Idempotent: Yes — gracefully handles cases where the hotspot is already
#             down.
set -e

echo "[INFO] Shutting down Lumina Hub Hotspot..."
sudo nmcli connection down LuminaHub 2>/dev/null
sudo nmcli connection down Hotspot 2>/dev/null

echo "[INFO] Searching for known networks (Home Wi-Fi)..."
# Restart NetworkManager so it automatically connects to the highest priority known network
sudo systemctl restart NetworkManager
sleep 3

echo "[SUCCESS] The Hub has been taken offline."
echo "Your server should now be reconnected to your home Wi-Fi."
echo "You can SSH back into the server from your laptop!"

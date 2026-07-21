#!/bin/bash
# Purpose: Display the hub's IP address and a scannable QR code for student access.
# Usage:   sudo ./show_hub_info.sh
# Idempotent: Yes -- read-only.

ACTIVE=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$ACTIVE" ]; then
  ACTIVE=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
if [ -z "$ACTIVE" ]; then
  ACTIVE="10.42.0.1"
fi

echo ""
echo "======================================"
echo "  Lumina Hub is serving at:"
echo "  http://$ACTIVE:8000"
echo "======================================"
echo ""

if command -v qrencode &>/dev/null; then
  echo "Scan this QR code with your phone to connect:"
  qrencode -t ANSIUTF8 "http://$ACTIVE:8000" 2>/dev/null
else
  echo "Install qrencode to see a QR code:"
  echo "  sudo apt install qrencode"
fi

echo ""
echo "Student instructions:"
echo "  1. Connect your phone to the LuminaHub WiFi"
echo "  2. Open a browser and go to: http://$ACTIVE:8000"
echo "  3. Download the app or start using the web portal"
echo ""

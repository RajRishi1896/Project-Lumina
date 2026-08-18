#!/bin/bash
# Purpose: Disable the LuminaHub hotspot AP and free the WiFi radio so the
#          laptop can join a normal WiFi network via nmtui. The ethernet
#          link and the hub API service (0.0.0.0:8000) stay untouched, so
#          SSH access and the Lumina API keep working.
# Usage:   sudo ./restore_ssh.sh
# Args:    none
# Idempotent: Yes -- re-running is a no-op once the hotspot is down.
set -e

# nmcli needs root to modify system connections.
if [ "$(id -u)" != "0" ]; then
    echo "Run with sudo: sudo ./restore_ssh.sh"
    exit 1
fi

# 1. Tear down the hotspot AP so the radio is free for client mode.
#    autoconnect is disabled so the AP does not come back on its own
#    while the laptop is used as a normal WiFi client.
if nmcli connection show LuminaHub >/dev/null 2>&1; then
    nmcli connection modify LuminaHub autoconnect no || true
    nmcli connection down LuminaHub || true
    echo "[OK] Hotspot 'LuminaHub' is down (autoconnect disabled)."
else
    echo "[INFO] No 'LuminaHub' hotspot connection -- nothing to tear down."
fi

# 2. Make sure the radio is on and scanning for client networks.
nmcli radio wifi on
nmcli device wifi rescan || true

# 3. Report status and what to do next.
nmcli device status
echo ""
echo "[NEXT] Available WiFi networks:"
nmcli device wifi list
echo ""
echo "Connect with: nmtui"
echo "Re-enable the hotspot by restarting the hub service:"
echo "  sudo systemctl restart lumina-hub.service"
echo "or manually:"
echo "  sudo nmcli connection modify LuminaHub autoconnect yes"
echo "  sudo nmcli connection up LuminaHub"

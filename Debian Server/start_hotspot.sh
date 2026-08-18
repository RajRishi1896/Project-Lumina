#!/bin/bash
# Purpose: Forcefully creates and activates the "Lumina Hub" Wi-Fi hotspot.
#          Takes control of the Wi-Fi card, kills conflicting processes,
#          configures NetworkManager with a WPA2-PSK profile, then forces
#          the widest channel width the adapter supports (80 MHz if possible).
# Usage:   sudo ./start_hotspot.sh
# Args:    None
# Idempotent: Yes -- deletes any existing LuminaHub connection profile before
#             recreating it.
set -e

echo "[INFO] Initializing Wi-Fi Hotspot (Lumina Hub)..."

# 1. Force NetworkManager to manage all interfaces
sudo sed -i 's/managed=false/managed=true/g' /etc/NetworkManager/NetworkManager.conf

# 2. Kill manual wpa_supplicant connections that are locking the device
killall wpa_supplicant 2>/dev/null || true

# 3. Restart NetworkManager to apply changes
sudo systemctl restart NetworkManager || true
echo "Waiting for NetworkManager to restart..."
# Wait until NM is actually back (boot can be slow) -- bounded, no hard sleep
for i in $(seq 1 30); do
    if nmcli -t -f RUNNING general status 2>/dev/null | grep -q running; then
        break
    fi
    sleep 1
done

# 4. Detect Wi-Fi interface and phy device dynamically
WIFI_IF=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
if [ -z "$WIFI_IF" ]; then
    echo "[ERROR] Could not detect a Wi-Fi interface."
    exit 1
fi
PHY_DEV=$(iw dev "$WIFI_IF" info 2>/dev/null | awk '/wiphy/{print $2}')
if [ -z "$PHY_DEV" ]; then
    PHY_DEV="phy0"
fi
IW="/usr/sbin/iw"

# Wait for NIC firmware to initialize (5GHz channels appear late)
echo "[INFO] Waiting for WiFi firmware to initialize..."
for i in 1 2 3 4 5; do
    if timeout 5 $IW list 2>/dev/null | grep -q "5180"; then
        break
    fi
    sleep 2
done
echo "[INFO] Found Wi-Fi interface: $WIFI_IF (phy: $PHY_DEV)"

# 5. Detect max supported channel width: 80 > 40 > 20
MAX_WIDTH="20"
if timeout 5 $IW list 2>/dev/null | grep -q "Supported Channel Width.*80"; then
    MAX_WIDTH="80"
elif timeout 5 $IW list 2>/dev/null | grep -q "HT40"; then
    MAX_WIDTH="40"
fi

# 6. Create a bulletproof Hotspot Connection Profile
echo "[INFO] Creating Hotspot Profile..."
sudo nmcli connection delete LuminaHub 2>/dev/null || true
sudo nmcli connection add type wifi ifname "$WIFI_IF" con-name LuminaHub autoconnect yes ssid "Lumina Hub"
sudo nmcli connection modify LuminaHub wifi-sec.key-mgmt wpa-psk wifi-sec.psk "lumina2026"

# 7. Read saved band preference (admin UI saves to data/band_pref.txt)
BAND_PREF="/home/project-lumina/Project-Lumina/data/band_pref.txt"
if [ -f "$BAND_PREF" ]; then
    SAVED_BAND=$(cat "$BAND_PREF" 2>/dev/null | tr -d '[:space:]')
fi

# Prefer 2.4GHz by default (wider range, better wall penetration).
# Admin UI saves preference to data/band_pref.txt; override with "a" for 5GHz.
CENTER_FREQ="5745"
if [ "$SAVED_BAND" = "a" ] && timeout 5 $IW list 2>/dev/null | grep -q "5180.*MHz"; then
    sudo nmcli connection modify LuminaHub 802-11-wireless.mode ap 802-11-wireless.band a 802-11-wireless.channel 149 ipv4.method shared
    echo "[INFO] Using 5GHz (channel 149, saved preference) -- max width: ${MAX_WIDTH} MHz"
else
    sudo nmcli connection modify LuminaHub 802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 1 ipv4.method shared
    MAX_WIDTH="20"
    echo "[INFO] Using 2.4GHz channel 1 (default, longest range)"
fi

# 7b. Disable autoconnect on every other wifi profile so no client connection
# can fight the AP for the radio on reboot (e.g. a saved home wifi).
for p in $(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless" && $1!="LuminaHub" {print $1}'); do
    sudo nmcli connection modify "$p" autoconnect no 2>/dev/null || true
done

echo "[INFO] Starting Hotspot (seizing Wi-Fi radio)..."
nmcli device disconnect "$WIFI_IF" 2>/dev/null || true
sudo nmcli radio wifi off
sleep 2
sudo nmcli radio wifi on
# Firmware re-init after the radio cycle takes ~10s -- up too early and the
# supplicant times out (~60s). Settle first, then confirm the device is free.
sleep 12
for i in $(seq 1 15); do
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$WIFI_IF" '$1==d {print $2}')
    [ "$STATE" = "disconnected" ] && break
    sleep 1
done
# Transient supplicant timeouts occur right after a radio cycle -- retry a
# few times, each attempt bounded so a hung activation can't stall boot.
for i in 1 2 3; do
    if timeout 20 nmcli connection up LuminaHub 2>/dev/null; then
        break
    fi
    sleep 2
done
# Wait for the AP to actually reach activated state
for i in $(seq 1 15); do
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$WIFI_IF" '$1==d {print $2}')
    [ "$STATE" = "connected" ] && break
    sleep 1
done
sleep 1

# 8. Force max channel width (NetworkManager defaults to 20 MHz in AP mode)
# For 80 MHz on channel 149, center freq = 5775. For 2.4GHz, just skip.
if [ "$MAX_WIDTH" = "80" ]; then
    sudo $IW dev "$WIFI_IF" set freq "$CENTER_FREQ" 80 5775 2>/dev/null && \
        echo "[INFO] Channel width forced to 80 MHz" || \
        echo "[WARN] Could not force 80 MHz, falling back to NM default"
elif [ "$MAX_WIDTH" = "40" ]; then
    echo "[INFO] 40 MHz channel width (NM default)"
fi

ACTUAL=$($IW dev "$WIFI_IF" info 2>/dev/null | awk '/width/{print $2}')
echo "[SUCCESS] Hotspot 'Lumina Hub' active -- ${ACTUAL:-unknown} channel width"

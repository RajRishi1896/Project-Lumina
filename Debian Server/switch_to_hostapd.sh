#!/bin/bash
# Two-step swap: NM starts AP (needs wpa_supplicant), then hostapd takes over
set -e

echo "=== Step 1: Unmask wpa_supplicant so NM can start AP ==="
sudo systemctl unmask wpa_supplicant 2>/dev/null || true
sudo systemctl start wpa_supplicant 2>/dev/null || true
sleep 2

# Clean up
sudo killall hostapd dnsmasq 2>/dev/null || true
sudo rm -f /etc/NetworkManager/conf.d/99-unmanaged-wifi.conf
sudo nmcli connection delete LuminaHub 2>/dev/null || true
sudo systemctl restart NetworkManager
sleep 4

# Create and start AP via NM
echo "=== Creating NM AP ==="
WIFI_IF=$(sudo nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')
echo "WiFi interface: $WIFI_IF"
sudo nmcli connection add type wifi ifname "$WIFI_IF" con-name LuminaHub autoconnect no ssid "Lumina Hub"
sudo nmcli connection modify LuminaHub wifi-sec.key-mgmt wpa-psk wifi-sec.psk "lumina2026"
sudo nmcli connection modify LuminaHub 802-11-wireless.mode ap 802-11-wireless.band a 802-11-wireless.channel 149 ipv4.method shared

sudo nmcli connection up LuminaHub
sleep 3

echo "=== NM AP running ==="
sudo /usr/sbin/iw dev "$WIFI_IF" info | grep -E 'type|channel|width'

# Step 2: Quickly swap to hostapd
echo "=== Step 2: Swapping to hostapd ==="
sudo nmcli connection down LuminaHub
sleep 1
sudo killall wpa_supplicant 2>/dev/null || true
sleep 1

# Start hostapd - interface should still be in AP mode
sudo /usr/sbin/hostapd /etc/hostapd/hostapd.conf -B -P /run/hostapd.pid 2>&1
sleep 2

# Force 80MHz
sudo /usr/sbin/iw dev "$WIFI_IF" set freq 5745 80 5775
sleep 1

# IP + DHCP
sudo /usr/sbin/ip addr add 10.42.0.1/24 dev "$WIFI_IF" 2>/dev/null || true
sudo /usr/sbin/dnsmasq --conf-file=/etc/dnsmasq-lumina.conf 2>&1 || true

echo "=== FINAL ==="
sudo /usr/sbin/iw dev "$WIFI_IF" info | grep -E 'type|channel|width'
sudo /usr/sbin/iw dev "$WIFI_IF" station dump 2>/dev/null | grep -E 'tx bitrate|rx bitrate|signal' || echo "(no clients yet)"

# Step 3: Lock down for future boots
sudo killall wpa_supplicant 2>/dev/null || true
sudo systemctl stop wpa_supplicant 2>/dev/null || true
sudo systemctl mask wpa_supplicant 2>/dev/null || true
sudo tee /etc/NetworkManager/conf.d/99-unmanaged-wifi.conf > /dev/null << EOF
[keyfile]
unmanaged-devices=interface-name:$WIFI_IF
EOF
echo "=== wpa_supplicant masked, WiFi unmanaged by NM ==="
echo "=== DONE ==="

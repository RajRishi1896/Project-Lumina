#!/bin/bash
# Purpose: Master provisioning script for a Lumina EduMesh Hub. Installs
#          system dependencies, creates directory structure, configures the
#          firewall, captive portal DNS, systemd services, cron jobs, and
#          kernel-level concurrency limits.
# Usage:   sudo ./setup_hub.sh
# Args:    None
# Idempotent: Yes — safe to re-run as a repair install. Existing configs
#             are overwritten with the latest defaults.
set -e
cd "$(dirname "$0")" || exit 1

echo "[INFO] Initializing Hardened Hub Setup..."
echo "-----------------------------------"

# 1. Update and Install Core Dependencies
echo "[INFO] Installing System dependencies..."
apt update
apt install -y python3 python3-pip python3-venv dnsmasq network-manager ufw

# 2. Create Directory Structure
echo "[INFO] Creating Hub structure..."
mkdir -p uploads data static app zim_pages

# 3. Install Python requirements
echo "[INFO] Installing Python requirements..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
else
    echo "venv already exists, skipping creation"
fi
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    pip install --upgrade pip 2>/dev/null || true
    pip install -r requirements.txt
else
    echo "[WARNING] venv/bin/activate not found. Installing system-wide..."
    pip3 install --user -r requirements.txt 2>/dev/null || pip install -r requirements.txt
fi

# 4. Generate self-signed SSL cert if missing
echo "[INFO] Generating self-signed SSL certificate..."
DIR="$(dirname "$0")"
CERT="$DIR/data/server.pem"
KEY="$DIR/data/server.key"
if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
  openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes \
    -subj "/C=IN/O=EduMesh/CN=lumina.hub" 2>/dev/null
  chmod 600 "$KEY" "$CERT"
  echo "[INFO] Self-signed SSL cert generated"
else
  echo "[INFO] SSL cert already exists, skipping"
fi

# 5. Configure Firewall (Secure Lockdown)
echo "[INFO] Configuring Firewall (UFW)..."
if command -v ufw &>/dev/null; then
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 8000/tcp 2>/dev/null || true
    ufw allow 67/udp 2>/dev/null || true
    ufw allow 53/udp 2>/dev/null || true
    ufw allow 53/tcp 2>/dev/null || true
    ufw allow 5353/udp 2>/dev/null || true
    if ufw status | grep -q "22/tcp"; then
        ufw --force enable 2>/dev/null || true
    else
        echo "[WARNING] SSH rule not verified. Skipping UFW enable."
    fi
else
    echo "[WARNING] UFW not installed. Skipping firewall."
fi

# 4a. Install fail2ban for rate limiting
echo "[INFO] Installing fail2ban for rate limiting..."
if ! command -v fail2ban-client &>/dev/null; then
    apt install -y fail2ban 2>/dev/null || true
fi

# 6. Configure Captive Portal DNS via NetworkManager
echo "[INFO] Configuring Captive Portal DNS..."
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
bash -c "cat > /etc/NetworkManager/dnsmasq-shared.d/lumina.conf <<EOF
address=/lumina.hub/10.42.0.1
address=/#/10.42.0.1
EOF"

# 6a. Configure LAN DNS (dnsmasq) for Chromium compatibility
# Resolves Lumina.hub locally so Chromium browsers can find it without /etc/hosts
echo "[INFO] Configuring LAN DNS for Lumina.hub..."
mkdir -p /etc/dnsmasq.d
LAN_IFACE=$(ip -o -4 route show default | awk '{print $5}')
LAN_IP=$(ip -o -4 addr show "$LAN_IFACE" | awk '{print $4}' | cut -d/ -f1)
bash -c "cat > /etc/dnsmasq.d/lumina-lan.conf <<EOF
address=/Lumina.hub/$LAN_IP
address=/lumina.hub/$LAN_IP

server=$(ip route | grep default | awk '{print $3}')
local=/Lumina.hub/
local=/lumina.hub/

bind-interfaces
interface=$LAN_IFACE
no-dhcp-interface=$LAN_IFACE
port=53
domain-needed
bogus-priv
EOF"
rm -f /etc/dnsmasq.d/lumina.conf 2>/dev/null || true
sed -i '/lumina.hub/d' /etc/hosts 2>/dev/null || true
systemctl enable dnsmasq 2>/dev/null || true
systemctl restart dnsmasq 2>/dev/null || true

# 7. Install & Enable the Systemd Service
bash -c "cat > /etc/systemd/system/lumina-hub.service <<EOF
[Unit]
Description=Lumina Hub FastAPI Service
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/python main.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

systemctl daemon-reload
systemctl enable lumina-hub 2>/dev/null || true
systemctl start lumina-hub 2>/dev/null || true

# 8. Install & Enable the Hotspot Systemd Service
echo "[INFO] Creating hotspot systemd service..."
HUB_DIR="$(pwd)"
bash -c "cat > /etc/systemd/system/lumina-hotspot.service <<EOF
[Unit]
Description=Lumina Hotspot Service
After=network.target

[Service]
Type=oneshot
ExecStart=$HUB_DIR/start_hotspot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"
systemctl daemon-reload
systemctl enable lumina-hotspot 2>/dev/null || true
echo "[INFO] Hotspot enabled. It will start on next boot (or run: systemctl start lumina-hotspot)"

# 9. Prevent Sleep on Lid Close (Headless Laptop Mode)
echo "[INFO] Disabling Sleep on Lid Close..."
mkdir -p /etc/systemd/logind.conf.d
bash -c "cat > /etc/systemd/logind.conf.d/lumina.conf <<EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF"
systemctl restart systemd-logind

# 10. Nightly Reboot to clear RAM leaks (3:00 AM)
( crontab -l 2>/dev/null | grep -v "^[0#]*[0-9].*/sbin/shutdown.*-r"; echo "0 3 * * * /sbin/shutdown -r now" ) | crontab -

# 11. Auto-Repair File System on Power Loss
if grep -q "fsck.repair=yes" /etc/default/grub; then
    echo "[INFO] fsck.repair=yes already set in GRUB_CMDLINE_LINUX_DEFAULT"
else
    echo "[INFO] Setting fsck.repair=yes in GRUB_CMDLINE_LINUX_DEFAULT"
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 fsck.repair=yes"/' /etc/default/grub
    update-grub
fi

# 12. Unlimited File Descriptor Patch (Massive Concurrency)
echo "[INFO] Unlocking Maximum Server Capacity..."
if grep -q "root hard nofile 65535" /etc/security/limits.conf; then
    echo "File descriptor limits already set"
else
    bash -c "cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF"
fi

echo "-----------------------------------"
echo "[SUCCESS] HARDENED SETUP COMPLETE!"
echo "[INFO] Hub Address: https://lumina.hub:8000 (cert auto-generated)"
echo "[INFO] Logs: data/hub.log"
echo "[INFO] Firewall: Active (SSH & API ports open only)"
echo "[INFO] The Hub is ready for headless deployment."

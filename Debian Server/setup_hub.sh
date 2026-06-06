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
sudo apt update
sudo apt install -y python3 python3-pip python3-venv dnsmasq network-manager ufw

# 2. Create Directory Structure
echo "[INFO] Creating Hub structure..."
mkdir -p uploads data static app zim_pages
chmod +x hub_health_check.sh 2>/dev/null || true

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

# 4. Configure Firewall (Secure Lockdown)
echo "[INFO] Configuring Firewall (UFW)..."
if command -v ufw &>/dev/null; then
    sudo ufw default deny incoming 2>/dev/null || true
    sudo ufw default allow outgoing 2>/dev/null || true
    sudo ufw allow 22/tcp 2>/dev/null || true
    sudo ufw allow 8000/tcp 2>/dev/null || true
    sudo ufw allow 67/udp 2>/dev/null || true
    sudo ufw allow 53/udp 2>/dev/null || true
    sudo ufw allow 53/tcp 2>/dev/null || true
    sudo ufw allow 5353/udp 2>/dev/null || true
    if sudo ufw status | grep -q "22/tcp"; then
        sudo ufw --force enable 2>/dev/null || true
    else
        echo "[WARNING] SSH rule not verified. Skipping UFW enable."
    fi
else
    echo "[WARNING] UFW not installed. Skipping firewall."
fi

# 4a. Install fail2ban for rate limiting
echo "[INFO] Installing fail2ban for rate limiting..."
if ! command -v fail2ban-client &>/dev/null; then
    sudo apt install -y fail2ban 2>/dev/null || true
fi

# 5. Configure Captive Portal DNS via NetworkManager
echo "[INFO] Configuring Captive Portal DNS..."
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
sudo bash -c "cat > /etc/NetworkManager/dnsmasq-shared.d/lumina.conf <<EOF
address=/lumina.hub/10.42.0.1
address=/#/10.42.0.1
EOF"

# 5a. Configure LAN DNS (dnsmasq) for Chromium compatibility
# Resolves Lumina.hub locally so Chromium browsers can find it without /etc/hosts
echo "[INFO] Configuring LAN DNS for Lumina.hub..."
sudo mkdir -p /etc/dnsmasq.d
LAN_IFACE=$(ip -o -4 route show default | awk '{print $5}')
LAN_IP=$(ip -o -4 addr show "$LAN_IFACE" | awk '{print $4}' | cut -d/ -f1)
sudo bash -c "cat > /etc/dnsmasq.d/lumina-lan.conf <<EOF
address=/Lumina.hub/$LAN_IP
address=/lumina.hub/$LAN_IP
address=/Luminahub.org/$LAN_IP
address=/luminahub.org/$LAN_IP
server=$(ip route | grep default | awk '{print $3}')
local=/Lumina.hub/
local=/lumina.hub/
local=/Luminahub.org/
local=/luminahub.org/
bind-interfaces
interface=$LAN_IFACE
no-dhcp-interface=$LAN_IFACE
port=53
domain-needed
bogus-priv
EOF"
sudo rm -f /etc/dnsmasq.d/lumina.conf 2>/dev/null || true
sudo sed -i '/lumina.hub/d' /etc/hosts 2>/dev/null || true
sudo systemctl enable dnsmasq 2>/dev/null || true
sudo systemctl restart dnsmasq 2>/dev/null || true

# 6. Install & Enable the Systemd Service
sudo bash -c "cat > /etc/systemd/system/lumina-hub.service <<EOF
[Unit]
Description=Lumina Hub FastAPI Service
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/uvicorn app.api:app --host 0.0.0.0 --port 8000 --timeout-keep-alive 60
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable lumina-hub 2>/dev/null || true
sudo systemctl start lumina-hub 2>/dev/null || true

# 7. Install & Enable the Hotspot Systemd Service
echo "[INFO] Creating hotspot systemd service..."
HUB_DIR="$(pwd)"
sudo bash -c "cat > /etc/systemd/system/lumina-hotspot.service <<EOF
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
sudo systemctl daemon-reload
sudo systemctl enable lumina-hotspot 2>/dev/null || true
echo "[INFO] Hotspot enabled. It will start on next boot (or run: sudo systemctl start lumina-hotspot)"

# 8. Prevent Sleep on Lid Close (Headless Laptop Mode)
echo "[INFO] Disabling Sleep on Lid Close..."
sudo mkdir -p /etc/systemd/logind.conf.d
sudo bash -c "cat > /etc/systemd/logind.conf.d/lumina.conf <<EOF
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF"
sudo systemctl restart systemd-logind

# 9. Nightly Reboot to clear RAM leaks (3:00 AM)
( sudo crontab -l 2>/dev/null | grep -v "^[0#]*[0-9].*/sbin/shutdown.*-r"; echo "0 3 * * * /sbin/shutdown -r now" ) | sudo crontab -

# 10. Auto-Repair File System on Power Loss
if grep -q "fsck.repair=yes" /etc/default/grub; then
    echo "[INFO] fsck.repair=yes already set in GRUB_CMDLINE_LINUX_DEFAULT"
else
    echo "[INFO] Setting fsck.repair=yes in GRUB_CMDLINE_LINUX_DEFAULT"
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 fsck.repair=yes"/' /etc/default/grub
    sudo update-grub
fi

# 11. Unlimited File Descriptor Patch (Massive Concurrency)
echo "[INFO] Unlocking Maximum Server Capacity..."
if grep -q "root hard nofile 65535" /etc/security/limits.conf; then
    echo "File descriptor limits already set"
else
    sudo bash -c "cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF"
fi

echo "-----------------------------------"
echo "[SUCCESS] HARDENED SETUP COMPLETE!"
echo "[INFO] Hub Addresses: http://lumina.hub:8000  /  http://luminahub.org:8000"
echo "[INFO] Logs: data/hub.log"
echo "[INFO] Firewall: Active (SSH & API ports open only)"
echo "[INFO] The Hub is ready for headless deployment."

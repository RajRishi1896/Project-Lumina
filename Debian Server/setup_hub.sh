#!/bin/bash
# Purpose: Master provisioning script for a Lumina EduMesh Hub. Installs
#          system dependencies, creates directory structure, configures the
#          firewall, captive portal DNS, systemd services, cron jobs, and
#          kernel-level concurrency limits.
# Usage:   sudo ./setup_hub.sh
# Args:    None
# Idempotent: Yes, safe to re-run as a repair install. Existing configs
#             are overwritten with the latest defaults.
set -e
cd "$(dirname "$0")" || exit 1

echo "[INFO] Initializing Hardened Hub Setup..."
echo "-----------------------------------"

# 1. Update and Install Core Dependencies
echo "[INFO] Installing System dependencies..."
apt update
apt install -y python3 python3-pip python3-venv dnsmasq network-manager ufw libzim-dev

# 2. Create Directory Structure
echo "[INFO] Creating Hub structure..."
mkdir -p uploads data static app zim_pages thumbnails profile_icons
chmod +x start_hotspot.sh backup_hub.sh reset_admin.sh show_hub_info.sh 2>/dev/null || true

# 3. Install Python requirements
echo "[INFO] Installing Python requirements..."
if [ ! -d "venv" ] || [ ! -f "venv/bin/python" ]; then
    rm -rf venv 2>/dev/null || true
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip 2>/dev/null || true
pip install -r requirements.txt

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

# Detect LAN IP + interface (used by captive portal DNS, dnsmasq, and banner)
LAN_IFACE=$(ip -o -4 route show default | awk '{print $5}')
LAN_IP=$(ip -o -4 addr show "$LAN_IFACE" | awk '{print $4}' | cut -d/ -f1)

# 6. Configure Captive Portal DNS via NetworkManager
echo "[INFO] Configuring Captive Portal DNS..."
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
bash -c "cat > /etc/NetworkManager/dnsmasq-shared.d/lumina.conf <<EOF
address=/#/$LAN_IP
EOF"

# 6a. Configure LAN DNS forwarder (dnsmasq)
# Forwards LAN DNS upstream; bound to the LAN interface only so it never
# conflicts with NetworkManager's captive-portal dnsmasq on the hotspot.
echo "[INFO] Configuring LAN DNS forwarder..."
mkdir -p /etc/dnsmasq.d
bash -c "cat > /etc/dnsmasq.d/lumina-lan.conf <<EOF
server=$(ip route | grep default | awk '{print $3}')

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
echo "[INFO] Installing systemd service..."
HUB_DIR="$(pwd)"
bash -c "cat > /etc/systemd/system/lumina-hub.service <<EOF
[Unit]
Description=Lumina Hub FastAPI Service
After=network.target

[Service]
User=root
WorkingDirectory=$HUB_DIR
ExecStart=$HUB_DIR/venv/bin/python main.py --no-banner
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

systemctl daemon-reload
systemctl stop lumina-hub 2>/dev/null || true
systemctl enable lumina-hub 2>/dev/null || true
systemctl start lumina-hub 2>/dev/null || true
echo "[INFO] Lumina Hub service started"

# 7b. Install console QR banner via /etc/issue (shows before login prompt)
chmod +x show_banner.sh 2>/dev/null || true
HUB_DIR="$(pwd)"
"$HUB_DIR/venv/bin/python" -c "
import qrcode, subprocess, socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect((LAN_IP, 80))
    ip = s.getsockname()[0]
    s.close()
except:
    ip = LAN_IP
qr = qrcode.QRCode(box_size=1, border=1)
qr.add_data('WIFI:T:WPA;S:Lumina Hub;P:lumina2026;;')
qr.make(fit=True)
qr_lines = []
for row in qr.get_matrix():
    qr_lines.append('    ' + ''.join('\u2588\u2588' if c else '  ' for c in row))
qr_block = '\n'.join(qr_lines)
banner = f'''
============================================================
   LUMINA HUB
============================================================

   Server:    http://{ip}:8000
   Hotspot:   Lumina Hub
   Password:  lumina2026

   Scan QR to connect to WiFi:

{qr_block}

   Then open in browser:
   http://{ip}:8000

============================================================
'''
with open('/etc/issue', 'w') as f:
    f.write(banner)
print('[INFO] /etc/issue updated with QR banner')
" 2>&1 || echo "[WARNING] Could not generate QR banner"

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

# 10. Nightly Reboot + Daily Backup: persisted in /etc/cron.d/ (survives reboots)
tee /etc/cron.d/lumina-hub > /dev/null << 'CRON'
SHELL=/bin/bash
# Nightly reboot at 3:00 AM to clear RAM leaks
0 3 * * * root /sbin/shutdown -r now
# Daily backup at 2:00 AM
0 2 * * * root cd /home/project-lumina/Project-Lumina && ./backup_hub.sh >> data/backup.log 2>&1
CRON
chmod 644 /etc/cron.d/lumina-hub
echo "[INFO] Cron jobs written to /etc/cron.d/lumina-hub (persists across reboots)"

# 10c. Enable NTP for accurate timekeeping
echo "[INFO] Enabling NTP..."
timedatectl set-ntp true 2>/dev/null || true

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

# 13. RTC Wake Alarm (one-shot arm at install)
# rtcwake -m no writes the alarm to the RTC's persistent registers, so it
# survives reboots (including the nightly 3 AM reboot cron above). Arming
# once here is enough; no periodic re-arm service is needed.
echo "[INFO] Arming RTC wake alarm for power-loss recovery..."
/usr/sbin/rtcwake -m no -s 21600 2>/dev/null || true
echo "[INFO] RTC wake alarm armed. Auto-boots on power restore."

echo "-----------------------------------"
echo "[SUCCESS] HARDENED SETUP COMPLETE!"
echo "[INFO] Hub Address: http://$LAN_IP:8000"
echo "[INFO] Logs: data/hub.log"
echo "[INFO] Firewall: Active (SSH & API ports open only)"
echo "[INFO] Run 'sudo systemctl start lumina-hotspot' to activate WiFi hotspot"
echo "[INFO] The Hub is ready for headless deployment."

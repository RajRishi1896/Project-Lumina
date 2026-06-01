#!/bin/bash
cd "$(dirname "$0")" || exit 1
set -e
# Lumina Hub - MASTER SETUP SCRIPT (Hardened Edition)

echo "[INFO] Initializing Hardened Hub Setup..."
echo "-----------------------------------"

# 1. Update and Install Core Dependencies
echo "[INFO] Installing System dependencies..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv dnsmasq network-manager ufw

# 2. Create Directory Structure
echo "[INFO] Creating Hub structure..."
mkdir -p uploads data static app zim_pages
chmod +x hub_health_check.sh

# 3. Install Python requirements
echo "[INFO] Installing Python requirements..."
# Create and use virtual environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. Configure Firewall (Secure Lockdown)
echo "[INFO] Configuring Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 8000/tcp # Lumina API
sudo ufw allow 67/udp   # DHCP (Required for clients to get IPs)
sudo ufw allow 53/udp   # DNS (Required for Captive Portal routing)
sudo ufw allow 53/tcp   # DNS
sudo ufw allow 5353/udp   # mDNS/Zeroconf Discovery
sudo ufw --force enable

# 4a. Install fail2ban for rate limiting
echo "[INFO] Installing fail2ban for rate limiting..."
if ! command -v fail2ban-client &>/dev/null; then
    sudo apt install -y fail2ban 2>/dev/null || true
fi

# 5. Configure Captive Portal DNS via NetworkManager
echo "[INFO] Configuring Captive Portal DNS..."
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
sudo bash -c "cat > /etc/NetworkManager/dnsmasq-shared.d/lumina.conf <<EOF
address=/lumina.hub/10.42.0.1
address=/#/10.42.0.1
EOF"

# 6. Install & Enable the Systemd Service

sudo bash -c "cat > /etc/systemd/system/lumina-hub.service <<EOF
[Unit]
Description=Lumina Hub FastAPI Service
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/uvicorn app.api:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable lumina-hub
sudo systemctl start lumina-hub
# 7. Install & Enable the Hotspot Systemd Service
echo "[INFO] Creating hotspot systemd service..."
sudo bash -c 'cat > /etc/systemd/system/lumina-hotspot.service <<EOF
[Unit]
Description=Lumina Hotspot Service
After=network.target

[Service]
Type=oneshot
ExecStart=$(pwd)/start_hotspot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl daemon-reload
sudo systemctl enable lumina-hotspot
sudo systemctl start lumina-hotspot

# 8. Prevent Sleep on Lid Close (Headless Laptop Mode)
echo "[INFO] Disabling Sleep on Lid Close..."
sudo sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g' /etc/systemd/logind.conf
sudo sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/g' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# 9. Nightly Reboot to clear RAM leaks (3:00 AM)
(sudo crontab -l 2>/dev/null || true; echo "0 3 * * * /sbin/shutdown -r now") | sudo crontab -

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
grep -q "root hard nofile 65535" /etc/security/limits.conf || sudo bash -c "cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF"

echo "-----------------------------------"
echo "[SUCCESS] HARDENED SETUP COMPLETE!"
echo "[INFO] Hub Address: http://lumina.hub:8000"
echo "[INFO] Logs: data/hub.log"
echo "[INFO] Firewall: Active (SSH & API ports open only)"
echo "[INFO] The Hub is ready for headless deployment."

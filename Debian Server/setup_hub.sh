#!/bin/bash
# Lumina Hub - MASTER SETUP SCRIPT (Hardened Edition)

echo "🏛️  Initializing Hardened Hub Setup..."
echo "-----------------------------------"

# 1. Update and Install Core Dependencies
echo "📦 Installing System dependencies..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv dnsmasq network-manager ufw

# 2. Create Directory Structure
echo "📂 Creating Hub structure..."
mkdir -p uploads data static app
chmod +x hub_health_check.sh

# 3. Install Python requirements
echo "🐍 Installing Python requirements..."
pip3 install -r requirements.txt --break-system-packages

# 4. Configure Firewall (Secure Lockdown)
echo "🛡️  Configuring Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 8000/tcp # Lumina API
sudo ufw allow 67/udp   # DHCP (Required for clients to get IPs)
sudo ufw allow 53/udp   # DNS (Required for Captive Portal routing)
sudo ufw allow 53/tcp   # DNS
sudo ufw --force enable

# 5. Disable System-Wide dnsmasq to prevent conflicts with NetworkManager
echo "🏷️  Disabling system-wide dnsmasq to allow NetworkManager AP mode..."
sudo systemctl disable dnsmasq 2>/dev/null
sudo systemctl stop dnsmasq 2>/dev/null

# 7. Install & Enable the Systemd Service
echo "⚙️  Configuring Auto-Start Service..."
sudo cp lumina-hub.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable lumina-hub
sudo systemctl start lumina-hub

# 8. Prevent Sleep on Lid Close (Headless Laptop Mode)
echo "💻 Disabling Sleep on Lid Close..."
sudo sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g' /etc/systemd/logind.conf
sudo sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/g' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# 9. Nightly Reboot to clear RAM leaks (3:00 AM)
(crontab -l 2>/dev/null | grep -v "/sbin/shutdown -r now"; echo "0 3 * * * /sbin/shutdown -r now") | sudo crontab -

# 10. Auto-Repair File System on Power Loss
grep -q "fsck.repair=yes" /etc/default/grub || sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="fsck.repair=yes /' /etc/default/grub
sudo update-grub

# 11. Unlimited File Descriptor Patch (Massive Concurrency)
echo "🚀 Unlocking Maximum Server Capacity..."
grep -q "root hard nofile 65535" /etc/security/limits.conf || sudo bash -c "cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF"

echo "-----------------------------------"
echo "✅ HARDENED SETUP COMPLETE!"
echo "📍 Hub Address: http://lumina.hub:8000"
echo "📜 Logs: data/hub.log"
echo "🛡️  Firewall: Active (SSH & API ports open only)"
echo "🚀 The Hub is ready for headless deployment."

#!/bin/bash
# Lumina Hub - Local DNS Configuration (Domain Setup)

DOMAIN="lumina.hub"
HUB_IP="192.168.1.1"

echo "🏷️ Setting up local domain: $DOMAIN -> $HUB_IP..."

# 1. Install dnsmasq
sudo apt update
sudo apt install -y dnsmasq

# 2. Configure dnsmasq to resolve our domain
sudo bash -c "cat > /etc/dnsmasq.d/lumina.conf <<EOF
address=/$DOMAIN/$HUB_IP
interface=lo
interface=wlan0  # Assuming WiFi mesh, change if ethernet
bind-interfaces
EOF"

# 3. Add to local hosts file for good measure
sudo bash -c "echo '$HUB_IP $DOMAIN' >> /etc/hosts"

# 4. Restart service
sudo systemctl restart dnsmasq

echo "✅ Success! You can now access the Hub at http://$DOMAIN:8000"

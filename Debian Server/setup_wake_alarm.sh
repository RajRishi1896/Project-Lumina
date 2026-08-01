#!/bin/bash
# Purpose: Install RTC wake alarm service that boots the laptop at 06:00 daily.
# Usage: sudo bash setup_wake_alarm.sh
# Idempotent: Yes — overwrites existing service file.

set -e

cat > /etc/systemd/system/wake-alarm.service << 'EOF'
[Unit]
Description=Set RTC wake alarm for 06:00 daily
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/sbin/rtcwake -m no -t $(date -d "tomorrow 06:00" +%s)'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wake-alarm.service
systemctl start wake-alarm.service
echo "wake-alarm.service installed and started."
echo "RTC alarm set for: $(date -d 'tomorrow 06:00')"
